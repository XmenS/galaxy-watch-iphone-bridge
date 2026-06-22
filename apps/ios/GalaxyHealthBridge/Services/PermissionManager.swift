import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasHealthKitAuth: Bool = false

    private let healthKit: HealthKitManager

    init(healthKit: HealthKitManager) {
        self.healthKit = healthKit
    }

    func requestHealthKit() async throws {
        try await healthKit.requestAuthorization()
        hasHealthKitAuth = true
    }
}
