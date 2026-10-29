import Foundation
import CliptCore

/// UserDefaults-backed settings. (`hotKey` arrives with HotKeys in a later task.)
@MainActor
final class Prefs {
    static let shared = Prefs()

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let maxItems = "retention.maxItems"
        static let maxAge = "retention.maxAge"
        static let ignoredApps = "ignoredApps"
        static let capturePaused = "capturePaused"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let motionEnabled = "motionEnabled"
        static let onboardingDone = "onboardingDone"
    }

    /// 0 in defaults means "unlimited" / "forever"; an absent key means the default.
    var retention: RetentionPolicy {
        get {
            var policy = RetentionPolicy.default
            if defaults.object(forKey: Key.maxItems) != nil {
                let n = defaults.integer(forKey: Key.maxItems)
                policy.maxItems = n > 0 ? n : nil
            }
            if defaults.object(forKey: Key.maxAge) != nil {
                let s = defaults.double(forKey: Key.maxAge)
                policy.maxAge = s > 0 ? s : nil
            }
            return policy
        }
        set {
            defaults.set(newValue.maxItems ?? 0, forKey: Key.maxItems)
            defaults.set(newValue.maxAge ?? 0, forKey: Key.maxAge)
        }
    }

    var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? CaptureFilter.defaultIgnoredApps }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    var capturePaused: Bool {
        get { defaults.bool(forKey: Key.capturePaused) }
        set { defaults.set(newValue, forKey: Key.capturePaused) }
    }

    var showMenuBarIcon: Bool {
        get { bool(Key.showMenuBarIcon, default: true) }
        set { defaults.set(newValue, forKey: Key.showMenuBarIcon) }
    }

    var motionEnabled: Bool {
        get { bool(Key.motionEnabled, default: true) }
        set { defaults.set(newValue, forKey: Key.motionEnabled) }
    }

    var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }
}
