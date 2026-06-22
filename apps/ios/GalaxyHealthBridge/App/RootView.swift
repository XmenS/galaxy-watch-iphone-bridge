import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HealthSummaryView()
                .tabItem { Label("Today", systemImage: "heart.fill") }

            BLESyncView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
}
