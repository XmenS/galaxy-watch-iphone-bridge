import Foundation

/// UserDefaults-backed store for the per-install state used by the BLE sync flow.
final class LocalStore {
    private let suite = UserDefaults.standard
    private let installIdKey = "ghb.install_id"
    private let cursorKey    = "ghb.sample_cursor"

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

    func clear() {
        suite.removeObject(forKey: cursorKey)
    }
}
