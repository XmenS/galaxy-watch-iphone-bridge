import Foundation
import os

/// Drives one BLE sync run: ask BLEClient for samples since our cursor, map them to
/// CanonicalSample, hand to HealthKitManager, advance the cursor.
@MainActor
final class BLESyncCoordinator: ObservableObject {

    @Published var status: String = "Idle"
    @Published var lastWritten: Int = 0
    @Published var lastSkipped: Int = 0
    @Published var isRunning: Bool = false
    @Published var error: String?

    private let client = BLEClient()
    private let hk: HealthKitManager
    private let store: LocalStore
    private let log = Logger(subsystem: "dev.galaxyhealthbridge", category: "ble.sync")

    private static let cursorKey = "ghb.ble_cursor_ms"

    init(hk: HealthKitManager = .live(), store: LocalStore = LocalStore()) {
        self.hk = hk
        self.store = store
    }

    var cursorMs: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: Self.cursorKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: Self.cursorKey) }
    }

    func runOnce(reset: Bool = false) async {
        guard !isRunning else { return }
        isRunning = true; error = nil; lastWritten = 0; lastSkipped = 0
        defer { isRunning = false }

        do {
            try await hk.requestAuthorization()
        } catch {
            self.error = error.localizedDescription
            return
        }

        var written = 0
        var skipped = 0
        let stream = client.sync(since: cursorMs, reset: reset)
        let work = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await event in stream {
                    switch event {
                    case .scanning:    self.status = "Scanning for watch…"
                    case .connecting(let name): self.status = "Connecting to \(name)…"
                    case .syncing:     self.status = "Syncing samples…"
                    case .batch(let items):
                        let mapped = items.compactMap { Self.toCanonical($0) }
                        let canonical = mapped.filter { SyncPreferences.isEnabled($0.type) }
                        if !canonical.isEmpty {
                            let outcome = try await self.hk.save(canonical)
                            written += outcome.written
                            skipped += outcome.skipped + (items.count - canonical.count)
                        } else {
                            skipped += items.count
                        }
                        self.status = "Wrote \(written) so far…"
                    case .readyToAcknowledge(let newest, let total):
                        self.status = "Confirming \(total) HealthKit records..."
                        self.client.acknowledgeHealthKitCommit(newestMs: newest, total: total)
                    case .done(let newest, let total):
                        if newest > self.cursorMs { self.cursorMs = newest }
                        self.status = "Done. \(total) sample\(total == 1 ? "" : "s") received."
                        self.lastWritten = written
                        self.lastSkipped = skipped
                    case .error(let e):
                        self.error = e.localizedDescription
                        self.status = "Failed."
                    }
                }
            } catch {
                self.error = error.localizedDescription
                self.status = "Failed."
            }
        }
        // Watchdog: if the BLE flow stalls (e.g. watch advertises but never streams
        // because of a CoreBluetooth ordering race), don't hang the UI forever.
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            guard let self = self, self.isRunning else { return }
            self.status = "Timed out waiting for watch."
            self.error = "Sync timed out after 20s. Make sure HealthBridge is running on the watch."
            work.cancel()
        }
        await work.value
        timeout.cancel()
    }

    /// Maps the Watch's compact wire `Sample` to the iOS `CanonicalSample` shape.
    /// Unknown types are returned as nil and counted as skipped.
    /// Internal-only `static` rather than `private` so the tests can drive it.
    nonisolated static func toCanonical(_ w: WireSample, now: Date = Date()) -> CanonicalSample? {
        let type: CanonicalSampleType?
        switch w.t {
        case "hr":     type = .heartRate
        case "steps":  type = .steps
        case "cal":    type = .activeEnergy
        case "dist":   type = .distance
        case "floors": type = .flightsClimbed
        case "workout": type = .workout
        case "sleep_in_bed": type = .sleepInBed
        case "sleep_awake":  type = .sleepAwake
        case "sleep_light":  type = .sleepLight
        case "sleep_deep":   type = .sleepDeep
        case "sleep_rem":    type = .sleepRem
        default: type = nil
        }
        guard let t = type else { return nil }

        let (startedAt, endedAt) = rebaseTimestamps(startMs: w.s, endMs: w.e, now: now)
        var metadata: [String: AnyCodable] = [:]
        if t == .workout {
            if let value = w.wt { metadata["workout_type"] = AnyCodable(value) }
            if let value = w.wd { metadata["distance_m"] = AnyCodable(value) }
            if let value = w.wc { metadata["calories_kcal"] = AnyCodable(value) }
            if let value = w.wh { metadata["average_hr"] = AnyCodable(value) }
        }
        return CanonicalSample(
            clientUid: w.uid,
            source: "GalaxyWatch",
            type: t,
            unit: w.u,
            value: w.v,
            startedAt: startedAt,
            endedAt: endedAt,
            metadata: metadata,
            nonceB64: nil,
            ciphertextB64: nil,
        )
    }

    /// Galaxy Watches that haven't been paired to a phone (this app's whole point)
    /// often have a wildly wrong wall clock — we've seen 14-month drifts. When the
    /// watch's reported timestamps land more than an hour outside the iPhone's
    /// current time, rebase the sample to iPhone-now while preserving the original
    /// duration. The temporal placement within the day is lost, but the daily
    /// totals stay correct and the samples actually land in today's HealthKit slot.
    nonisolated static func rebaseTimestamps(startMs: Int64, endMs: Int64, now: Date = Date()) -> (Date, Date) {
        let originalStart = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0)
        let originalEnd   = Date(timeIntervalSince1970: TimeInterval(endMs)   / 1000.0)
        let driftSeconds = abs(now.timeIntervalSince(originalEnd))
        if driftSeconds < 3600 {
            return (originalStart, originalEnd)
        }
        let duration = max(0, originalEnd.timeIntervalSince(originalStart))
        let rebasedEnd = now
        let rebasedStart = now.addingTimeInterval(-duration)
        return (rebasedStart, rebasedEnd)
    }
}
