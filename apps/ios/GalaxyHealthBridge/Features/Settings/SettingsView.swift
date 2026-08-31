import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var coordinator: BLESyncCoordinator
    @State private var store = LocalStore()
    @State private var showResetConfirm = false
    @State private var showWipeConfirm = false
    @State private var showFullResetConfirm = false
    @State private var wipeStatus: String?
    @State private var wiping = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                healthSection
                metricsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Reset all sync state?",
                isPresented: $showFullResetConfirm, titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { fullReset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes watch data from Apple Health, clears the sync cursor, and resets the watch's local buffer. Cannot be undone.")
            }
        }
    }

    // MARK: – Sections

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("This device").font(.subheadline.weight(.semibold))
                    Text(store.installId).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        } header: { Text("Account") }
    }

    private var healthSection: some View {
        Section {
            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Label("Open Apple Health", systemImage: "heart.text.square")
            }
            Text("Health → Browse → pick a category → tap a metric → Show All Data — entries from Galaxy Health Bridge appear there.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("To change permissions: Health → profile → Apps and Services → Galaxy Health Bridge.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Apple Health") }
    }

    private var metricsSection: some View {
        Section {
            ForEach(CanonicalSampleType.allCases, id: \.self) { metric in
                Toggle(isOn: enabledBinding(for: metric)) {
                    HStack(spacing: 12) {
                    Image(systemName: metric.iconName)
                        .font(.subheadline)
                        .foregroundStyle(metric.tintColor)
                        .frame(width: 30, height: 30)
                        .background(metric.tintColor.opacity(0.15), in: Circle())
                    Text(metric.displayName)
                    }
                }
                .disabled(metric.healthKitWriteType == nil)
            }
        } header: { Text("What this app syncs") } footer: {
            Text("Disabled rows have no safe HealthKit mapping. Changes apply to the next sync.")
                .font(.caption2)
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showFullResetConfirm = true
            } label: {
                if wiping {
                    HStack { ProgressView(); Text("Resetting…") }
                } else {
                    Label("Reset everything", systemImage: "arrow.counterclockwise.circle")
                }
            }
            .disabled(wiping)
            if let wipeStatus {
                Text(wipeStatus).font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Reset") } footer: {
            Text("Deletes watch data from Apple Health, clears the sync cursor, and tells the watch to wipe its local buffer. The next sync re-pulls today's totals from scratch.")
                .font(.caption2)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(.secondary).monospacedDigit()
            }
            Link(destination: URL(string: "https://github.com/galaxy-health-bridge/galaxy-health-bridge")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: URL(string: "https://github.com/galaxy-health-bridge/galaxy-health-bridge/issues")!) {
                Label("Report an issue", systemImage: "exclamationmark.bubble")
            }
        } header: { Text("About") } footer: {
            Text("Galaxy Health Bridge is open source. No cloud account, no telemetry.")
                .font(.caption2)
        }
    }

    // MARK: – Actions

    /// Atomic "give me a clean slate" operation. Performs each step in dependency
    /// order so we can never end up with HealthKit data wiped but cursor still
    /// pointing into the void (or vice-versa). All cleanup happens before the
    /// reset sync runs so the watch's buffer wipe is the last thing to fail.
    private func fullReset() {
        wiping = true
        wipeStatus = "Resetting…"
        Task {
            defer { wiping = false }
            do {
                let hk = HealthKitManager.live()
                wipeStatus = "Deleting watch samples from Apple Health…"
                let n = try await hk.deleteAllWatchSamples()
                wipeStatus = "Deleted \(n). Clearing local state…"
                coordinator.cursorMs = 0
                store.clear()
                wipeStatus = "Asking watch to reset its buffer…"
                await coordinator.runOnce(reset: true)
                wipeStatus = coordinator.error.map { "Watch reset done. Sync error: \($0)" }
                    ?? "Reset complete. Wrote \(coordinator.lastWritten) fresh samples."
            } catch {
                wipeStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func enabledBinding(for metric: CanonicalSampleType) -> Binding<Bool> {
        Binding(
            get: { SyncPreferences.isEnabled(metric) },
            set: { SyncPreferences.setEnabled($0, for: metric) }
        )
    }
}
