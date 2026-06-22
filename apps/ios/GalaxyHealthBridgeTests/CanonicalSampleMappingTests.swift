import HealthKit
import XCTest
@testable import GalaxyHealthBridge

final class CanonicalSampleMappingTests: XCTestCase {
    func testHeartRateMaps() throws {
        let s = CanonicalSample(
            clientUid: "uid-1",
            source: "samsung-health",
            type: .heartRate,
            unit: "bpm",
            value: 72,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: [:],
            nonceB64: nil,
            ciphertextB64: nil
        )
        let sample = try XCTUnwrap(s.toHKSample() as? HKQuantitySample)
        XCTAssertEqual(sample.quantityType.identifier, HKQuantityTypeIdentifier.heartRate.rawValue)
        XCTAssertEqual(sample.quantity.doubleValue(for: HKUnit(from: "count/min")), 72)
    }

    func testSleepDeepMaps() throws {
        let s = CanonicalSample(
            clientUid: "uid-sleep",
            source: "samsung-health",
            type: .sleepDeep,
            unit: nil,
            value: nil,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60 * 30),
            metadata: [:],
            nonceB64: nil,
            ciphertextB64: nil
        )
        let cat = try XCTUnwrap(s.toHKSample() as? HKCategorySample)
        XCTAssertEqual(cat.categoryType.identifier, HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        XCTAssertEqual(cat.value, HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
    }

    func testWorkoutTypeReturnsNilForNow() {
        let s = CanonicalSample(
            clientUid: "u",
            source: "x",
            type: .workout,
            unit: nil,
            value: nil,
            startedAt: Date(),
            endedAt: Date(),
            metadata: [:],
            nonceB64: nil,
            ciphertextB64: nil
        )
        // Workouts use HKWorkoutBuilder; mapper intentionally returns nil until implemented.
        XCTAssertNil(s.toHKSample())
    }
}
