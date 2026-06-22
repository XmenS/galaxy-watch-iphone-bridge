import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var session: SessionStore
    @State private var pairCode: String = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Pair with Android") {
                    Text("Enter the pair code from the Android app. The code expires in 5 minutes.")
                        .foregroundStyle(.secondary)
                    TextField("GH-XX-XX-XX", text: $pairCode)
                        .textCase(.uppercase)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("2. HealthKit access") {
                    Button {
                        Task { try? await session.permissions.requestHealthKit() }
                    } label: { Text("Grant HealthKit access") }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(action: link) {
                        if busy { ProgressView() } else { Text("Link this iPhone") }
                    }
                    .disabled(pairCode.count < 8 || busy)
                }
            }
            .navigationTitle("Galaxy Health Bridge")
        }
    }

    private func link() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let pair = try await session.api.redeemPairCode(
                    .init(code: pairCode,
                          installId: session.store.installId,
                          deviceKind: "ios",
                          deviceLabel: UIDevice.current.name,
                          pubKey: nil)
                )
                session.store.accessToken = pair.accessToken
                session.store.refreshToken = pair.refreshToken
                try await session.permissions.requestHealthKit()
                session.didCompleteOnboarding()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
