import XCTest
@testable import GalaxyHealthBridge

final class BLESyncCoordinatorTests: XCTestCase {

    // MARK: rebaseTimestamps

    func testRebaseKeepsTimestampsWhenWatchClockIsCorrect() {
        // Sample 5 seconds ago, watch and phone agree on time.
        let now = Date()
        let endMs = Int64(now.timeIntervalSince1970 * 1000) - 5_000
        let startMs = endMs - 60_000
        let (start, end) = BLESyncCoordinator.rebaseTimestamps(startMs: startMs, endMs: endMs, now: now)
        // Within 1 second of the original
        XCTAssertLessThan(abs(end.timeIntervalSince1970 * 1000 - Double(endMs)), 1)
        XCTAssertLessThan(abs(start.timeIntervalSince1970 * 1000 - Double(startMs)), 1)
    }

    func testRebaseRewritesTimestampsWhenWatchClockIsWildlyOff() {
        // Watch reports a sample from 14 months ago (its clock is wrong). Phone is now.
        let now = Date(timeIntervalSince1970: 1_782_500_000) // some "now"
        let endMs: Int64 = 1_743_225_734_066 // ~456 days earlier — the real bug we hit
        let durationMs: Int64 = 60_000
        let startMs = endMs - durationMs
        let (start, end) = BLESyncCoordinator.rebaseTimestamps(startMs: startMs, endMs: endMs, now: now)
        // Sample must be rebased to "now", duration preserved.
        XCTAssertEqual(end.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        let actualDuration = end.timeIntervalSince(start)
        XCTAssertEqual(actualDuration, TimeInterval(durationMs) / 1000.0, accuracy: 0.01)
    }

    func testRebaseHandlesZeroDuration() {
        // Heart-rate samples have start == end (instant).
        let now = Date(timeIntervalSince1970: 1_782_500_000)
        let endMs: Int64 = 1_743_225_734_066
        let (start, end) = BLESyncCoordinator.rebaseTimestamps(startMs: endMs, endMs: endMs, now: now)
        XCTAssertEqual(start, end)
        XCTAssertEqual(end.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: toCanonical

    func testStepsWireSampleMapsToStepsTypeWithDailyTotal() throws {
        // Watch sends a daily-total sample: uid "steps-day-N", value 313 = today's total.
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let wire = WireSample(uid: "steps-day-2026-173", t: "steps", v: 313, u: "count",
                              s: nowMs - 60_000, e: nowMs)
        let canonical = try XCTUnwrap(BLESyncCoordinator.toCanonical(wire, now: now))
        XCTAssertEqual(canonical.type, .steps)
        XCTAssertEqual(canonical.value, 313)
        XCTAssertEqual(canonical.clientUid, "steps-day-2026-173")
        XCTAssertEqual(canonical.source, "GalaxyWatch")
    }

    func testLegacyActiveCaloriesWireSampleMaps() throws {
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let wire = WireSample(uid: "cal-day-2026-173", t: "cal", v: 17.0, u: "kcal",
                              s: nowMs - 60_000, e: nowMs)
        let canonical = try XCTUnwrap(BLESyncCoordinator.toCanonical(wire, now: now))
        XCTAssertEqual(canonical.type, .activeEnergy)
        XCTAssertEqual(canonical.value, 17.0)
    }

    func testTotalCaloriesAreNotMisrepresentedAsActiveEnergy() {
        let wire = WireSample(uid: "cal-total", t: "cal_total", v: 2100, u: "kcal", s: 1_700_000_000_000, e: 1_700_000_001_000)
        XCTAssertNil(BLESyncCoordinator.toCanonical(wire))
    }

    func testFloorsMapToFlightsClimbed() throws {
        let wire = WireSample(uid: "floors-1", t: "floors", v: 6, u: "count", s: 1_700_000_000_000, e: 1_700_000_001_000)
        let canonical = try XCTUnwrap(BLESyncCoordinator.toCanonical(wire))
        XCTAssertEqual(canonical.type, .flightsClimbed)
        XCTAssertEqual(canonical.value, 6)
    }

    func testWorkoutMapsWithMetrics() throws {
        let wire = WireSample(
            uid: "walk-1", t: "workout", v: nil, u: nil,
            s: 1_700_000_000_000, e: 1_700_000_600_000,
            wt: "walking", wd: 850, wc: 62, wh: 113
        )
        let canonical = try XCTUnwrap(BLESyncCoordinator.toCanonical(wire))
        XCTAssertEqual(canonical.type, .workout)
        XCTAssertEqual(canonical.metadata["distance_m"]?.doubleValue, 850)
        let workout = try XCTUnwrap(canonical.toHKSample() as? HKWorkout)
        XCTAssertEqual(workout.workoutActivityType, .walking)
    }

    func testDistanceWireSampleMaps() throws {
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let wire = WireSample(uid: "dist-day-2026-173", t: "dist", v: 237.0, u: "m",
                              s: nowMs - 60_000, e: nowMs)
        let canonical = try XCTUnwrap(BLESyncCoordinator.toCanonical(wire, now: now))
        XCTAssertEqual(canonical.type, .distance)
        XCTAssertEqual(canonical.value, 237.0)
    }

    func testUnknownWireTypeReturnsNil() {
        let wire = WireSample(uid: "u-1", t: "unknown_type", v: 1.0, u: nil,
                              s: 0, e: 0)
        XCTAssertNil(BLESyncCoordinator.toCanonical(wire))
    }

    // MARK: hk save dedup contract (compile-time check that clientUid carries through)

    func testToHKSampleEmbedsClientUidInMetadata() throws {
        let s = CanonicalSample(
            clientUid: "steps-day-2026-173",
            source: "GalaxyWatch",
            type: .steps, unit: "count", value: 313,
            startedAt: Date(timeIntervalSince1970: 1_782_500_000 - 60),
            endedAt: Date(timeIntervalSince1970: 1_782_500_000),
            metadata: [:], nonceB64: nil, ciphertextB64: nil
        )
        let hk = try XCTUnwrap(s.toHKSample())
        let uid = hk.metadata?["GHBClientUid"] as? String
        XCTAssertEqual(uid, "steps-day-2026-173")
        let src = hk.metadata?["GHBSource"] as? String
        XCTAssertEqual(src, "GalaxyWatch")
    }
}
