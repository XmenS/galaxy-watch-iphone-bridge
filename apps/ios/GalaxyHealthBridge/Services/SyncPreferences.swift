import Foundation

enum SyncPreferences {
    private static let prefix = "ghb.sync.enabled."

    static func isEnabled(_ type: CanonicalSampleType, defaults: UserDefaults = .standard) -> Bool {
        let key = prefix + type.rawValue
        return defaults.object(forKey: key) == nil ? type.healthKitWriteType != nil : defaults.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, for type: CanonicalSampleType, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: prefix + type.rawValue)
    }
}
