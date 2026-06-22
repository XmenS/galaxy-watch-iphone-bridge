import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    enum State { case loading, needsOnboarding, signedIn }

    @Published private(set) var state: State = .loading
    let api: ApiClient
    let healthKit: HealthKitManager
    let permissions: PermissionManager
    let store: LocalStore

    init(
        api: ApiClient = .live(),
        healthKit: HealthKitManager = .live(),
        store: LocalStore = LocalStore()
    ) {
        self.api = api
        self.healthKit = healthKit
        self.permissions = PermissionManager(healthKit: healthKit)
        self.store = store
    }

    func bootstrap() async {
        if store.refreshToken != nil {
            state = .signedIn
        } else {
            state = .needsOnboarding
        }
    }

    func didCompleteOnboarding() {
        state = .signedIn
    }

    func signOut() {
        store.clear()
        state = .needsOnboarding
    }

    static var preview: SessionStore { SessionStore() }
}
