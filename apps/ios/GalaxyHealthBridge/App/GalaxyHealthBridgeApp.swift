import SwiftUI

@main
struct GalaxyHealthBridgeApp: App {
    @StateObject private var coordinator = BLESyncCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
    }
}
