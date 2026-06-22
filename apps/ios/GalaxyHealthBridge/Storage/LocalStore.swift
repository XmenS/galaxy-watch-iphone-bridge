import Foundation

/// Tiny KV-style store over Keychain for tokens + UserDefaults for non-secret state.
final class LocalStore {
    private let suite = UserDefaults.standard
    private let installIdKey = "ghb.install_id"
    private let cursorKey    = "ghb.sample_cursor"
    private let keychain     = Keychain(service: "dev.galaxyhealthbridge.tokens")

    var installId: String {
        if let s = suite.string(forKey: installIdKey) { return s }
        let new = UUID().uuidString
        suite.set(new, forKey: installIdKey)
        return new
    }

    var cursor: String? {
        get { suite.string(forKey: cursorKey) }
        set { suite.set(newValue, forKey: cursorKey) }
    }

    var refreshToken: String? {
        get { keychain.string(forKey: "refresh") }
        set { keychain.set(newValue, forKey: "refresh") }
    }

    var accessToken: String? {
        get { keychain.string(forKey: "access") }
        set { keychain.set(newValue, forKey: "access") }
    }

    func clear() {
        suite.removeObject(forKey: cursorKey)
        keychain.set(nil, forKey: "access")
        keychain.set(nil, forKey: "refresh")
    }
}
