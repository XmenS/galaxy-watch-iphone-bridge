import SwiftUI
import HealthKit
import UIKit
import Charts

@MainActor
final class HealthSummaryViewModel: ObservableObject {
    @Published var snapshot = TodaySnapshot()
    @Published var loading = false
    @Published var error: String?
    @Published var lastRefreshedAt: Date?
    @Published var authSummary: HealthKitAuthSummary = .needsPrompt

    private let hk: HealthKitManager

    init(hk: HealthKitManager = .live()) { self.hk = hk }

    func refresh(coordinator: BLESyncCoordinator? = nil, kickBle: Bool = true) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        // Refresh auth state first so we know whether we can sync.
        self.authSummary = hk.writeAuthSummary
        // Don't auto-trigger BLE sync until HealthKit is granted — calling
        // requestAuthorization mid-task can render as an empty system sheet.
        if kickBle, authSummary == .granted,
           let coordinator = coordinator, !coordinator.isRunning {
            await coordinator.runOnce()
        }
        self.snapshot = await hk.todaySnapshot()
        self.lastRefreshedAt = Date()
        self.error = nil
    }

    func grantHealthKit() async {
        do {
            try await hk.requestAuthorization()
            self.authSummary = hk.writeAuthSummary
            self.snapshot = await hk.todaySnapshot()
            self.lastRefreshedAt = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct HealthSummaryView: View {
    @StateObject private var vm = HealthSummaryViewModel()
    @EnvironmentObject private var coordinator: BLESyncCoordinator
    @Environment(\.openURL) private var openURL

    private static let autoSyncIntervalSeconds: UInt64 = 30

    private let twoCol = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let threeCol = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    headerCard

                    if vm.authSummary != .granted {
                        HealthAccessCard(
                            summary: vm.authSummary,
                            onGrant: { Task { await vm.grantHealthKit() } },
                            onOpenHealth: {
                                if let url = URL(string: "x-apple-health://") { openURL(url) }
                            }
                        )
                    }

                    SyncStatusBar(coordinator: coordinator, vm: vm)

                    ActivityRingsCard(
                        activeKcal: vm.snapshot.readings[.activeEnergy]?.value ?? 0,
                        moveGoal: 500,
                        steps: vm.snapshot.readings[.steps]?.value ?? 0,
                        stepsGoal: 10_000,
                        exerciseMinutes: vm.snapshot.exerciseMinutesToday,
                        exerciseGoal: 30
                    )

                    LazyVGrid(columns: threeCol, spacing: 12) {
                        HeroTile(metric: .activeEnergy, reading: vm.snapshot.readings[.activeEnergy])
                        HeroTile(metric: .steps, reading: vm.snapshot.readings[.steps])
                        HeroTile(metric: .heartRate, reading: vm.snapshot.readings[.heartRate])
                    }

                    HeartRateChartCard(
                        points: vm.snapshot.heartRateSeries,
                        latestBpm: vm.snapshot.readings[.heartRate]?.value
                    )

                    StepsChartCard(points: vm.snapshot.hourlySteps)

                    ActiveEnergyChartCard(points: vm.snapshot.hourlyActiveEnergy)

                    sectionGrid(
                        title: "Heart & respiratory",
                        systemImage: "heart.text.square.fill",
                        accent: .red,
                        metrics: [.restingHeartRate, .hrv, .spo2, .respiratoryRate]
                    )

                    sectionGrid(
                        title: "Activity & energy",
                        systemImage: "figure.run",
                        accent: .green,
                        metrics: [.distance, .basalEnergy, .vo2Max]
                    )

                    sectionGrid(
                        title: "Body",
                        systemImage: "person.fill",
                        accent: .brown,
                        metrics: [.bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyTemperature,
                                  .bloodPressureSystolic, .bloodPressureDiastolic]
                    )

                    sectionGrid(
                        title: "Sleep (last 24h)",
                        systemImage: "bed.double.fill",
                        accent: .indigo,
                        metrics: [.sleepInBed, .sleepDeep, .sleepLight, .sleepRem, .sleepAwake]
                    )

                    workoutsSection

                    DataSourcesCard(
                        stepsBySource: vm.snapshot.stepsBySource,
                        caloriesBySource: vm.snapshot.caloriesBySource,
                        heartRateBySource: vm.snapshot.heartRateBySource
                    )

                    appleHealthCTA

                    if let err = vm.error {
                        errorCard(err)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .refreshable { await vm.refresh(coordinator: coordinator, kickBle: true) }
            // The .task closure is created when the view appears and cancelled when it
            // disappears, so this gives us a self-stopping foreground sync loop.
            //
            // We intentionally do NOT auto-call HealthKit auth here. On iOS 17+ the
            // system sheet sometimes renders as an empty black overlay when triggered
            // from .task (the view is still settling its layout). The HealthAccessCard
            // gives the user an explicit Grant access button instead.
            .task {
                while !Task.isCancelled {
                    await vm.refresh(coordinator: coordinator, kickBle: true)
                    let ns = Self.autoSyncIntervalSeconds * 1_000_000_000
                    try? await Task.sleep(nanoseconds: ns)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh(coordinator: coordinator, kickBle: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.loading || coordinator.isRunning)
                }
            }
        }
    }

    // MARK: – Subviews

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.title2.bold())
                Text(Date(), format: .dateTime.month(.wide).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if vm.loading || coordinator.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(coordinator.isRunning ? "Syncing watch…" : "Reading HealthKit…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let ts = vm.lastRefreshedAt {
                    Text("Updated \(ts.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Auto-sync · every 30s")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func sectionGrid(
        title: String, systemImage: String, accent: Color,
        metrics: [CanonicalSampleType]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, systemImage: systemImage, accent: accent)
            LazyVGrid(columns: twoCol, spacing: 12) {
                ForEach(metrics, id: \.self) { metric in
                    MetricTile(metric: metric, reading: vm.snapshot.readings[metric])
                }
            }
        }
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Workouts today", systemImage: "figure.strengthtraining.traditional", accent: .orange)
            if vm.snapshot.workouts.isEmpty {
                EmptyStateCard(
                    icon: "figure.walk.motion",
                    title: vm.loading ? "Loading workouts…" : "No workouts logged yet",
                    subtitle: vm.loading ? nil : "Start a workout on your Galaxy Watch and tap Sync."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.snapshot.workouts) { WorkoutCard(workout: $0) }
                }
            }
        }
    }

    private var appleHealthCTA: some View {
        Button {
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.pink, .red],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Apple Health").font(.headline)
                    Text("See every sample, grouped by source")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Something went wrong").font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: – Reusable components

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(accent)
            Text(title)
                .font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct HeroTile: View {
    let metric: CanonicalSampleType
    let reading: MetricReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: metric.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(metric.tintColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(MetricFormatter.primaryValue(for: metric, reading: reading))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(MetricFormatter.unit(for: metric, reading: reading))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            Text(metric.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [metric.tintColor.opacity(0.18), metric.tintColor.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(metric.tintColor.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct MetricTile: View {
    let metric: CanonicalSampleType
    let reading: MetricReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: metric.iconName)
                    .font(.subheadline)
                    .foregroundStyle(metric.tintColor)
                    .frame(width: 30, height: 30)
                    .background(metric.tintColor.opacity(0.15), in: Circle())
                Spacer()
                if let ts = reading?.lastSampleAt {
                    Text(ts, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(metric.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(MetricFormatter.primaryValue(for: metric, reading: reading))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(MetricFormatter.unit(for: metric, reading: reading))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(MetricFormatter.subtitle(for: reading))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WorkoutCard: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [.orange, .pink],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(workout.activityName).font(.headline)
                    Spacer()
                    Text(workout.end, style: .time)
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    StatChip(icon: "clock", text: formatDuration(seconds: workout.duration))
                    if let kcal = workout.activeCalories {
                        StatChip(icon: "flame.fill", text: "\(Int(kcal)) kcal", tint: .orange)
                    }
                    if let m = workout.distanceMeters, m > 0 {
                        StatChip(icon: "location", text: String(format: "%.2f km", m / 1000.0), tint: .green)
                    }
                }
                Text("Source: \(workout.source)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatChip: View {
    let icon: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint)
            Text(text).font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let s = subtitle {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: – Formatting

private enum MetricFormatter {

    static func primaryValue(for metric: CanonicalSampleType, reading: MetricReading?) -> String {
        guard let r = reading, let v = r.value else { return "—" }
        switch r.aggregation {
        case .sleepDurationSeconds:
            return formatDurationShort(seconds: v)
        case .sumToday:
            return numberString(v, decimals: metric == .distance ? 1 : 0)
        case .latest:
            return numberString(v, decimals: latestDecimals(for: metric))
        case .unsupported:
            return "—"
        }
    }

    static func unit(for metric: CanonicalSampleType, reading: MetricReading?) -> String {
        guard let r = reading else { return "" }
        if r.aggregation == .sleepDurationSeconds { return "" }   // value already includes units
        if r.value == nil { return "" }
        return r.displayUnit
    }

    static func subtitle(for reading: MetricReading?) -> String {
        guard let r = reading else { return "Loading…" }
        if r.value == nil {
            switch r.aggregation {
            case .unsupported: return "Not synced"
            case .sumToday:    return "No data today"
            case .latest:      return "No samples yet"
            case .sleepDurationSeconds: return "No sleep recorded"
            }
        }
        switch r.aggregation {
        case .sumToday: return "Sum since midnight"
        case .latest:   return "Most recent reading"
        case .sleepDurationSeconds: return "Total in last 24h"
        case .unsupported: return ""
        }
    }

    private static func latestDecimals(for metric: CanonicalSampleType) -> Int {
        switch metric {
        case .bodyMass, .leanBodyMass, .bodyFatPercentage,
             .bodyTemperature, .hrv, .vo2Max:
            return 1
        default:
            return 0
        }
    }
}

private func numberString(_ v: Double, decimals: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = decimals
    f.minimumFractionDigits = decimals
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(decimals)f", v)
}

private func formatDuration(seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m) min" }
    return "\(total) sec"
}

private func formatDurationShort(seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// MARK: - HealthKit access card

private struct HealthAccessCard: View {
    let summary: HealthKitAuthSummary
    let onGrant: () -> Void
    let onOpenHealth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.pink, .red],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button(action: onGrant) {
                    Text(summary == .denied ? "Open Apple Health" : "Grant access")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                if summary == .denied {
                    Button(action: onOpenHealth) {
                        Text("Open Health app")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.pink.opacity(0.25), lineWidth: 1)
        )
    }

    private var title: String {
        switch summary {
        case .needsPrompt: return "Allow Apple Health access"
        case .denied:      return "Apple Health access denied"
        case .granted:     return "Apple Health connected"
        }
    }

    private var subtitle: String {
        switch summary {
        case .needsPrompt:
            return "Steps, heart rate, sleep and more need permission before they can sync."
        case .denied:
            return "Open Health → Profile → Apps and Services → Galaxy Health Bridge and enable each metric."
        case .granted:
            return "Reading from HealthKit."
        }
    }
}

// MARK: - Sync status banner

private struct SyncStatusBar: View {
    @ObservedObject var coordinator: BLESyncCoordinator
    @ObservedObject var vm: HealthSummaryViewModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(dotColor.opacity(0.2))
                Circle().fill(dotColor).frame(width: 10, height: 10)
                    .opacity(coordinator.isRunning ? 0.8 : 1)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine).font(.subheadline.weight(.semibold))
                Text(secondaryLine).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.isRunning {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(dotColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var dotColor: Color {
        if coordinator.error != nil { return .red }
        if coordinator.isRunning { return .blue }
        if coordinator.lastWritten > 0 { return .green }
        return .secondary
    }

    private var primaryLine: String {
        if let err = coordinator.error, !err.isEmpty {
            return "Sync failed"
        }
        if coordinator.isRunning {
            return coordinator.status
        }
        if let ts = vm.lastRefreshedAt {
            return "Last sync \(ts.formatted(date: .omitted, time: .standard))"
        }
        return "Waiting for first sync…"
    }

    private var secondaryLine: String {
        if let err = coordinator.error, !err.isEmpty {
            return err
        }
        let cursor = coordinator.cursorMs
        let cursorStr: String
        if cursor > 0 {
            let d = Date(timeIntervalSince1970: TimeInterval(cursor) / 1000.0)
            cursorStr = "cursor: " + d.formatted(date: .omitted, time: .standard)
        } else {
            cursorStr = "cursor: never"
        }
        return "wrote \(coordinator.lastWritten) · skipped \(coordinator.lastSkipped) · \(cursorStr)"
    }
}

// MARK: - Activity rings

private struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6), value: progress)
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(color.opacity(0.55),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct ActivityRingsCard: View {
    let activeKcal: Double
    let moveGoal: Double
    let steps: Double
    let stepsGoal: Double
    let exerciseMinutes: Double
    let exerciseGoal: Double

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ActivityRing(progress: activeKcal / moveGoal, color: .red, lineWidth: 12)
                ActivityRing(progress: steps / stepsGoal, color: .green, lineWidth: 12)
                    .padding(16)
                ActivityRing(progress: exerciseMinutes / exerciseGoal, color: .blue, lineWidth: 12)
                    .padding(32)
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 10) {
                RingLegend(
                    color: .red, title: "Move",
                    value: "\(Int(activeKcal)) / \(Int(moveGoal))",
                    unit: "kcal"
                )
                RingLegend(
                    color: .green, title: "Steps",
                    value: "\(Int(steps)) / \(Int(stepsGoal))",
                    unit: "steps"
                )
                RingLegend(
                    color: .blue, title: "Exercise",
                    value: "\(Int(exerciseMinutes)) / \(Int(exerciseGoal))",
                    unit: "min"
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RingLegend: View {
    let color: Color
    let title: String
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.subheadline.bold().monospacedDigit())
                    Text(unit).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Chart cards

private struct ChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.headline)
                Spacer()
                if let s = subtitle {
                    Text(s).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            content
                .frame(height: 150)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct HeartRateChartCard: View {
    let points: [TimeSeriesPoint]
    let latestBpm: Double?

    var body: some View {
        ChartCard(
            title: "Heart rate",
            systemImage: "waveform.path.ecg",
            tint: .red,
            subtitle: subtitle
        ) {
            if points.isEmpty {
                ChartEmptyState(text: "No heart-rate samples in the last 12 hours")
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("BPM", p.value)
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", p.date),
                        y: .value("BPM", p.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.red.opacity(0.35), .red.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
    }

    private var subtitle: String {
        if let v = latestBpm { return "\(Int(v)) bpm now" }
        return "Last 12h"
    }
}

private struct StepsChartCard: View {
    let points: [TimeSeriesPoint]

    var body: some View {
        ChartCard(
            title: "Steps by hour",
            systemImage: "figure.walk",
            tint: .green,
            subtitle: total
        ) {
            if points.allSatisfy({ $0.value == 0 }) {
                ChartEmptyState(text: "No steps logged in the last 12 hours")
            } else {
                Chart(points) { p in
                    BarMark(
                        x: .value("Hour", p.date, unit: .hour),
                        y: .value("Steps", p.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .mint],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
            }
        }
    }

    private var total: String {
        let sum = points.reduce(0) { $0 + Int($1.value) }
        return "\(sum) total"
    }
}

private struct ActiveEnergyChartCard: View {
    let points: [TimeSeriesPoint]

    var body: some View {
        ChartCard(
            title: "Active calories",
            systemImage: "flame.fill",
            tint: .orange,
            subtitle: total
        ) {
            if points.allSatisfy({ $0.value == 0 }) {
                ChartEmptyState(text: "No active energy in the last 12 hours")
            } else {
                Chart(points) { p in
                    AreaMark(
                        x: .value("Hour", p.date),
                        y: .value("kcal", p.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .orange.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Hour", p.date),
                        y: .value("kcal", p.value)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
            }
        }
    }

    private var total: String {
        let sum = points.reduce(0.0) { $0 + $1.value }
        return "\(Int(sum)) kcal"
    }
}

private struct ChartEmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Data sources card

private struct DataSourcesCard: View {
    let stepsBySource: [SourceContribution]
    let caloriesBySource: [SourceContribution]
    let heartRateBySource: [SourceContribution]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundStyle(.teal)
                Text("From your Galaxy Watch").font(.headline)
                Spacer()
            }

            SourceRow(title: "Steps", unit: "steps", icon: "figure.walk", tint: .green,
                      sources: stepsBySource, decimals: 0)
            Divider()
            SourceRow(title: "Active calories", unit: "kcal", icon: "flame.fill", tint: .orange,
                      sources: caloriesBySource, decimals: 0)
            Divider()
            SourceRow(title: "Heart rate (latest)", unit: "bpm", icon: "heart.fill", tint: .red,
                      sources: heartRateBySource, decimals: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SourceRow: View {
    let title: String
    let unit: String
    let icon: String
    let tint: Color
    let sources: [SourceContribution]
    let decimals: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
            }
            if sources.isEmpty {
                Text("No samples today").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(sources) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: s.isThisApp ? "iphone.radiowaves.left.and.right" : "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(s.isThisApp ? tint : .secondary)
                        Text(s.sourceName)
                            .font(.caption)
                            .lineLimit(1)
                        if s.isThisApp {
                            Text("watch").font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(tint)
                        }
                        Spacer()
                        Text("\(numberString(s.total, decimals: decimals)) \(unit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

#Preview { HealthSummaryView() }
