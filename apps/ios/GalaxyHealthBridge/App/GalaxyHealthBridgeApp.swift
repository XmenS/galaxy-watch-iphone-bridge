import SwiftUI

@main
struct GalaxyHealthBridgeApp: App {
    @StateObject private var coordinator = BLESyncCoordinator()
    @StateObject private var notificationBridge = PeripheralManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
    }
}
