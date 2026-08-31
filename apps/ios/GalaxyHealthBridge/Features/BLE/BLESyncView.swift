import SwiftUI
import CoreBluetooth

struct BLESyncView: View {
    @EnvironmentObject private var coordinator: BLESyncCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    statsCard
                    diagnosticsCard
                    syncButton
                    if let err = coordinator.error, !err.isEmpty {
                        errorCard(err)
                    }
                    helpCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sync")
        }
    }

    // MARK: – Cards

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(dotColor.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: dotIcon)
                    .font(.title2)
                    .foregroundStyle(dotColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryTitle).font(.headline)
                Text(coordinator.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.isRunning {
                ProgressView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last sync").font(.headline)
            Text(coordinator.lastSyncAt?.formatted(date: .abbreviated, time: .standard) ?? "Never")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                stat(label: "Written", value: "\(coordinator.lastWritten)", tint: .green)
                stat(label: "Skipped", value: "\(coordinator.lastSkipped)", tint: .orange)
                stat(label: "Cursor", value: cursorLabel, tint: .blue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics").font(.headline)
            diagnosticRow("Bluetooth", bluetoothAuthorization)
            diagnosticRow("Watch cursor", coordinator.cursorMs > 0 ? "Available" : "No completed sync")
            DisclosureGroup("HealthKit write permissions") {
                ForEach(Array(coordinator.healthAuthorizationDetails.enumerated()), id: \.offset) { _, row in
                    diagnosticRow(row.0, row.1)
                }
                Text("Apple does not disclose read-denial status to apps.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func diagnosticRow(_ name: String, _ value: String) -> some View {
        HStack { Text(name).font(.caption); Spacer(); Text(value).font(.caption).foregroundStyle(.secondary) }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var syncButton: some View {
        Button {
            Task { await coordinator.runOnce() }
        } label: {
            HStack(spacing: 8) {
                if coordinator.isRunning {
                    ProgressView().tint(.white)
                    Text("Syncing…")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync via Bluetooth")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.blue, .purple],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .disabled(coordinator.isRunning)
        .buttonStyle(.plain)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync failed").font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to sync", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            help("1.", "Open HealthBridge on the Galaxy Watch and tap Start.")
            help("2.", "Make sure the watch is unlocked and near the iPhone.")
            help("3.", "Tap Sync via Bluetooth above.")
            help("4.", "Approve Health permissions on the first run.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func help(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num).font(.caption.monospacedDigit().bold()).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.primary)
        }
    }

    // MARK: – Helpers

    private var dotColor: Color {
        if coordinator.error != nil { return .red }
        if coordinator.isRunning { return .blue }
        if coordinator.lastWritten > 0 { return .green }
        return .secondary
    }

    private var dotIcon: String {
        if coordinator.error != nil { return "exclamationmark.triangle.fill" }
        if coordinator.isRunning { return "antenna.radiowaves.left.and.right" }
        if coordinator.lastWritten > 0 { return "checkmark.circle.fill" }
        return "applewatch"
    }

    private var primaryTitle: String {
        if coordinator.error != nil { return "Sync failed" }
        if coordinator.isRunning { return "Syncing your watch" }
        if coordinator.lastWritten > 0 { return "Watch connected" }
        return "Ready to sync"
    }

    private var cursorLabel: String {
        let ms = coordinator.cursorMs
        if ms <= 0 { return "—" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return d.formatted(date: .omitted, time: .shortened)
    }

    private var bluetoothAuthorization: String {
        switch CBManager.authorization {
        case .allowedAlways: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }
}

#Preview { BLESyncView() }
