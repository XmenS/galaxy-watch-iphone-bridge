import Foundation
import HealthKit

/// Wraps HealthKit reads & writes. Single source of truth for type mappings.
final class HealthKitManager {
    static let isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    static func live() -> HealthKitManager { .init() }

    // MARK: – Authorization

    /// Types we may write to HealthKit. Keep in sync with the backend's canonical list.
    var writeTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = []
        for canonical in CanonicalSampleType.allCases {
            if let t = canonical.healthKitWriteType { set.insert(t) }
        }
        return set
    }

    /// Read types we may need to dedupe against HealthKit's existing data and surface
    /// in the Today summary screen.
    var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        for canonical in CanonicalSampleType.allCases {
            if let t = canonical.healthKitReadType { set.insert(t) }
        }
        set.insert(HKObjectType.workoutType())
        return set
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        // Skip the system auth sheet if every write type is already decided.
        // iOS renders the sheet as an empty overlay when nothing actually
        // needs prompting, so we avoid calling it then.
        let needsPrompt = writeTypes.contains { type in
            store.authorizationStatus(for: type) == .notDetermined
        }
        guard needsPrompt else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Coarse summary of write auth: nothing requested → .needsPrompt, all denied
    /// → .denied, otherwise .granted. Used by the dashboard to surface an empty
    /// state with a "Grant access" button instead of a blank screen.
    var writeAuthSummary: HealthKitAuthSummary {
        var anyAuthorized = false
        var anyDenied = false
        var anyNotDetermined = false
        for t in writeTypes {
            switch store.authorizationStatus(for: t) {
            case .sharingAuthorized:   anyAuthorized = true
            case .sharingDenied:       anyDenied = true
            case .notDetermined:       anyNotDetermined = true
            @unknown default:          anyNotDetermined = true
            }
        }
        if anyAuthorized { return .granted }
        if anyNotDetermined { return .needsPrompt }
        if anyDenied { return .denied }
        return .needsPrompt
    }

    var authorizationDetails: [(String, String)] {
        CanonicalSampleType.allCases.compactMap { canonical in
            guard let type = canonical.healthKitWriteType else { return nil }
            let status: String
            switch store.authorizationStatus(for: type) {
            case .sharingAuthorized: status = "Write allowed"
            case .sharingDenied: status = "Write denied"
            case .notDetermined: status = "Not requested"
            @unknown default: status = "Unknown"
            }
            return (canonical.displayName, status)
        }
    }

    // MARK: – Writing

    /// Persists a batch of canonical samples to HealthKit. Each sample carries its
    /// own `clientUid` in metadata as `GHBClientUid`; before saving we delete any
    /// existing HK sample with the same `GHBClientUid` so that "daily total"
    /// updates (which share a stable uid for the whole day) replace the prior
    /// row instead of duplicating. Per-event samples have unique uids so the
    /// dedup query simply finds no match.
    func save(_ samples: [CanonicalSample]) async throws -> WriteOutcome {
        let mapped: [(CanonicalSample, HKSample)] = samples.compactMap { sample in
            sample.toHKSample().map { (sample, $0) }
        }
        if mapped.isEmpty {
            return .init(written: 0, skipped: samples.count)
        }
        // Group by HK sample type so each dedup pass targets one type at a time
        // (HKQuery requires a concrete sampleType).
        let bySampleType = Dictionary(grouping: mapped) { (_, hk) in hk.sampleType }
        for (sampleType, group) in bySampleType {
            let uids = group.map { $0.0.clientUid }
            try? await deleteSamples(of: sampleType, withClientUids: Set(uids))
        }
        let hkSamples = mapped.map { $0.1 }
        try await store.save(hkSamples)
        return .init(written: hkSamples.count, skipped: samples.count - hkSamples.count)
    }

    /// Deletes every HealthKit sample of `type` whose `GHBClientUid` metadata is in `uids`.
    /// Used by `save()` to make daily-total writes idempotent. Failures are non-fatal —
    /// they just mean the write will append rather than replace, which is recoverable
    /// the next sync.
    private func deleteSamples(of type: HKSampleType, withClientUids uids: Set<String>) async throws {
        guard !uids.isEmpty else { return }
        let perUidPredicates = uids.map {
            HKQuery.predicateForObjects(withMetadataKey: "GHBClientUid", operatorType: .equalTo, value: $0)
        }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: perUidPredicates)
        let store = self.store
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let items = samples ?? []
                if items.isEmpty { cont.resume(returning: ()); return }
                store.delete(items) { _, derr in
                    if let derr = derr { cont.resume(throwing: derr) } else { cont.resume(returning: ()) }
                }
            }
            store.execute(q)
        }
    }
}

struct WriteOutcome: Equatable {
    let written: Int
    let skipped: Int
}

enum HealthKitAuthSummary { case needsPrompt, granted, denied }

// MARK: – Reading back what HealthKit has

struct MetricReading: Equatable {
    let value: Double?
    let displayUnit: String
    let lastSampleAt: Date?
    let aggregation: Aggregation

    enum Aggregation { case sumToday, latest, sleepDurationSeconds, unsupported }

    static let empty = MetricReading(value: nil, displayUnit: "", lastSampleAt: nil, aggregation: .unsupported)
}

struct WorkoutSummary: Identifiable, Equatable {
    let id: UUID
    let activityName: String
    let start: Date
    let end: Date
    let duration: TimeInterval
    let activeCalories: Double?
    let distanceMeters: Double?
    let source: String
}

struct TimeSeriesPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct SourceContribution: Identifiable, Equatable {
    var id: String { sourceName }
    let sourceName: String
    let total: Double
    let lastAt: Date?
    let isThisApp: Bool
}

struct TodaySnapshot: Equatable {
    var readings: [CanonicalSampleType: MetricReading] = [:]
    var workouts: [WorkoutSummary] = []
    var heartRateSeries: [TimeSeriesPoint] = []
    var hourlySteps: [TimeSeriesPoint] = []
    var hourlyActiveEnergy: [TimeSeriesPoint] = []
    var exerciseMinutesToday: Double = 0
    var stepsBySource: [SourceContribution] = []
    var caloriesBySource: [SourceContribution] = []
    var heartRateBySource: [SourceContribution] = []
}

extension HealthKitManager {

    /// Matches only samples that came from the Galaxy Watch via this app. We tagged
    /// every write with `GHBSource = "GalaxyWatch"` in `CanonicalSample.toHKSample`,
    /// so this lets the dashboard show watch-only numbers — no iPhone pedometer or
    /// third-party contributions.
    static let watchOnlyPredicate: NSPredicate = HKQuery.predicateForObjects(
        withMetadataKey: "GHBSource",
        operatorType: .equalTo,
        value: "GalaxyWatch"
    )

    /// Watch-only samples within [start, end].
    private static func watchOnlyInRange(_ start: Date, _ end: Date) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: []),
            watchOnlyPredicate,
        ])
    }

    /// Reads today's value for every canonical metric plus any workouts done today.
    /// Errors per-metric are swallowed so one missing permission doesn't blank the whole screen.
    /// Deletes every HealthKit sample we ever wrote (matched by our `GHBSource`
    /// metadata). Useful when the data model changes (e.g., switching from
    /// cumulative to delta steps) and old samples would skew totals.
    func deleteAllWatchSamples() async throws -> Int {
        // Ensure we have HealthKit auth before any read or delete; otherwise
        // HKHealthStore throws "authorization not determined" on the first query.
        try await requestAuthorization()
        var totalDeleted = 0
        var failures: [String] = []
        for type in writeTypes {
            do {
                totalDeleted += try await deleteSamples(of: type)
            } catch {
                // Per-type write auth may have been denied; skip and continue
                // rather than failing the whole wipe.
                failures.append("\(type.identifier): \(error.localizedDescription)")
            }
        }
        // Reset the BLE cursor so we re-pull everything from the watch's buffer next sync.
        UserDefaults.standard.removeObject(forKey: "ghb.ble_cursor_ms")
        UserDefaults.standard.removeObject(forKey: "ghb.sample_cursor")
        if totalDeleted == 0 && !failures.isEmpty {
            throw HealthKitError.notAuthorized(typeId: failures.first ?? "all")
        }
        return totalDeleted
    }

    private func deleteSamples(of type: HKSampleType) async throws -> Int {
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: Self.watchOnlyPredicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let items = samples ?? []
                if items.isEmpty { cont.resume(returning: 0); return }
                store.delete(items) { _, err in
                    if let err = err { cont.resume(throwing: err); return }
                    cont.resume(returning: items.count)
                }
            }
            store.execute(q)
        }
    }

    func todaySnapshot() async -> TodaySnapshot {
        guard Self.isAvailable else { return TodaySnapshot() }
        var snapshot = TodaySnapshot()
        for metric in CanonicalSampleType.allCases {
            snapshot.readings[metric] = await reading(for: metric)
        }
        snapshot.workouts = (try? await todaysWorkouts()) ?? []
        snapshot.heartRateSeries = (try? await heartRateSeries()) ?? []
        snapshot.hourlySteps = (try? await hourlyTotals(.stepCount, unit: .count(), hours: 12)) ?? []
        snapshot.hourlyActiveEnergy = (try? await hourlyTotals(.activeEnergyBurned, unit: .kilocalorie(), hours: 12)) ?? []
        snapshot.exerciseMinutesToday = snapshot.workouts.reduce(0) { $0 + $1.duration / 60.0 }
        snapshot.stepsBySource = (try? await sumBySource(.stepCount, unit: .count(), aggregate: .sum)) ?? []
        snapshot.caloriesBySource = (try? await sumBySource(.activeEnergyBurned, unit: .kilocalorie(), aggregate: .sum)) ?? []
        snapshot.heartRateBySource = (try? await sumBySource(.heartRate, unit: HKUnit(from: "count/min"), aggregate: .latest)) ?? []
        return snapshot
    }

    private enum SourceAggregate { case sum, latest }

    private func sumBySource(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, aggregate: SourceAggregate) async throws -> [SourceContribution] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = Self.watchOnlyInRange(start, Date())
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: qt, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let quantities = (samples ?? []).compactMap { $0 as? HKQuantitySample }
                let grouped = Dictionary(grouping: quantities) { $0.sourceRevision.source.name }
                let contributions = grouped.map { (name, list) -> SourceContribution in
                    let bundleID = list.first?.sourceRevision.source.bundleIdentifier ?? ""
                    switch aggregate {
                    case .sum:
                        let total = list.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                        let last = list.map(\.endDate).max()
                        return SourceContribution(sourceName: name, total: total, lastAt: last,
                                                  isThisApp: bundleID == myBundleID)
                    case .latest:
                        let latest = list.max(by: { $0.endDate < $1.endDate })
                        let v = latest?.quantity.doubleValue(for: unit) ?? 0
                        return SourceContribution(sourceName: name, total: v, lastAt: latest?.endDate,
                                                  isThisApp: bundleID == myBundleID)
                    }
                }
                cont.resume(returning: contributions.sorted { $0.total > $1.total })
            }
            store.execute(q)
        }
    }

    private func heartRateSeries(hoursBack: Int = 12, limit: Int = 200) async throws -> [TimeSeriesPoint] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: end) ?? end
        let predicate = Self.watchOnlyInRange(start, end)
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(
                sampleType: qt, predicate: predicate,
                limit: limit, sortDescriptors: [sort]
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let points = (samples ?? []).compactMap { $0 as? HKQuantitySample }.map {
                    TimeSeriesPoint(date: $0.startDate, value: $0.quantity.doubleValue(for: HKUnit(from: "count/min")))
                }
                cont.resume(returning: points)
            }
            store.execute(q)
        }
    }

    private func hourlyTotals(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, hours: Int) async throws -> [TimeSeriesPoint] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let end = Date()
        let calendar = Calendar.current
        let anchorHour = calendar.date(bySetting: .minute, value: 0, of: end) ?? end
        let start = calendar.date(byAdding: .hour, value: -hours, to: anchorHour) ?? anchorHour
        let predicate = Self.watchOnlyInRange(start, end)
        let interval = DateComponents(hour: 1)
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: qt, quantitySamplePredicate: predicate,
                options: [.cumulativeSum], anchorDate: start, intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, err in
                if let err = err { cont.resume(throwing: err); return }
                var points: [TimeSeriesPoint] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let v = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                    points.append(TimeSeriesPoint(date: stats.startDate, value: v))
                }
                cont.resume(returning: points)
            }
            store.execute(q)
        }
    }

    private func reading(for metric: CanonicalSampleType) async -> MetricReading {
        let unitLabel = displayUnitLabel(for: metric)

        if metric.healthKitCategoryType != nil, let sleepValue = metric.sleepCategoryValue {
            do {
                let (duration, last) = try await sleepDurationLast24h(stage: sleepValue)
                return MetricReading(
                    value: duration, displayUnit: unitLabel,
                    lastSampleAt: last, aggregation: .sleepDurationSeconds
                )
            } catch {
                return MetricReading(value: nil, displayUnit: unitLabel, lastSampleAt: nil, aggregation: .sleepDurationSeconds)
            }
        }
        guard let qt = metric.healthKitQuantityType, let hkUnit = metric.healthKitUnit else {
            return MetricReading(value: nil, displayUnit: unitLabel, lastSampleAt: nil, aggregation: .unsupported)
        }
        if isCumulative(metric) {
            do {
                let (sum, last) = try await sumToday(qt, unit: hkUnit)
                return MetricReading(
                    value: convertedForDisplay(metric, raw: sum),
                    displayUnit: unitLabel, lastSampleAt: last, aggregation: .sumToday
                )
            } catch {
                return MetricReading(value: nil, displayUnit: unitLabel, lastSampleAt: nil, aggregation: .sumToday)
            }
        } else {
            do {
                let (val, when) = try await mostRecent(qt, unit: hkUnit)
                return MetricReading(
                    value: convertedForDisplay(metric, raw: val),
                    displayUnit: unitLabel, lastSampleAt: when, aggregation: .latest
                )
            } catch {
                return MetricReading(value: nil, displayUnit: unitLabel, lastSampleAt: nil, aggregation: .latest)
            }
        }
    }

    private func isCumulative(_ m: CanonicalSampleType) -> Bool {
        switch m {
        case .steps, .distance, .flightsClimbed, .activeEnergy, .basalEnergy: return true
        default: return false
        }
    }

    private func displayUnitLabel(for m: CanonicalSampleType) -> String {
        switch m {
        case .steps:                                 return "steps"
        case .distance:                              return "km"
        case .flightsClimbed:                        return "floors"
        case .activeEnergy, .basalEnergy:            return "kcal"
        case .heartRate, .restingHeartRate:          return "bpm"
        case .hrv:                                   return "ms"
        case .spo2, .bodyFatPercentage:              return "%"
        case .respiratoryRate:                       return "br/min"
        case .bodyTemperature:                       return "°C"
        case .bloodPressureSystolic,
             .bloodPressureDiastolic:                return "mmHg"
        case .bodyMass, .leanBodyMass:               return "kg"
        case .vo2Max:                                return "ml/kg·min"
        case .sleepInBed, .sleepAwake, .sleepLight,
             .sleepDeep, .sleepRem:                  return "duration"
        default:                                     return ""
        }
    }

    private func convertedForDisplay(_ m: CanonicalSampleType, raw: Double?) -> Double? {
        guard let v = raw else { return nil }
        switch m {
        case .distance: return v / 1000.0           // meters → km
        default:        return v
        }
    }

    private func sumToday(_ qt: HKQuantityType, unit: HKUnit) async throws -> (Double?, Date?) {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = Self.watchOnlyInRange(start, Date())
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: qt,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum]
            ) { _, stats, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: (
                    stats?.sumQuantity()?.doubleValue(for: unit),
                    stats?.mostRecentQuantityDateInterval()?.end
                ))
            }
            store.execute(q)
        }
    }

    private func mostRecent(_ qt: HKQuantityType, unit: HKUnit) async throws -> (Double?, Date?) {
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(
                sampleType: qt, predicate: Self.watchOnlyPredicate, limit: 1, sortDescriptors: [sort]
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                guard let s = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: (nil, nil)); return
                }
                cont.resume(returning: (s.quantity.doubleValue(for: unit), s.endDate))
            }
            store.execute(q)
        }
    }

    private func sleepDurationLast24h(stage: HKCategoryValueSleepAnalysis) async throws -> (Double?, Date?) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (nil, nil)
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end) ?? end
        let predicate = Self.watchOnlyInRange(start, end)
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let matching = (samples ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .filter { $0.value == stage.rawValue }
                let total = matching.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let last = matching.map(\.endDate).max()
                cont.resume(returning: (matching.isEmpty ? nil : total, last))
            }
            store.execute(q)
        }
    }

    func todaysWorkouts(limit: Int = 10) async throws -> [WorkoutSummary] {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = Self.watchOnlyInRange(start, Date())
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let workouts = (samples ?? []).compactMap { sample -> WorkoutSummary? in
                    guard let w = sample as? HKWorkout else { return nil }
                    let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let meters = w.totalDistance?.doubleValue(for: .meter())
                    return WorkoutSummary(
                        id: w.uuid,
                        activityName: workoutName(w.workoutActivityType),
                        start: w.startDate,
                        end: w.endDate,
                        duration: w.duration,
                        activeCalories: kcal,
                        distanceMeters: meters,
                        source: w.sourceRevision.source.name
                    )
                }
                cont.resume(returning: workouts)
            }
            store.execute(q)
        }
    }
}

private func workoutName(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running:                 return "Run"
    case .walking:                 return "Walk"
    case .cycling:                 return "Cycling"
    case .traditionalStrengthTraining,
         .functionalStrengthTraining: return "Strength"
    case .highIntensityIntervalTraining: return "HIIT"
    case .yoga:                    return "Yoga"
    case .swimming:                return "Swim"
    case .rowing:                  return "Rowing"
    case .elliptical:              return "Elliptical"
    case .stairClimbing:           return "Stair climbing"
    case .hiking:                  return "Hike"
    case .dance:                   return "Dance"
    case .mixedCardio:             return "Cardio"
    case .other:                   return "Workout"
    default:                       return "Workout"
    }
}

enum HealthKitError: Error, LocalizedError {
    case unavailable
    case notAuthorized(typeId: String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "HealthKit is not available on this device."
        case .notAuthorized(let id): return "Not authorized to write to \(id)."
        }
    }
}
