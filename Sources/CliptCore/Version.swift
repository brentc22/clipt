import Foundation

public enum CliptVersion {
    /// The marketing version from the app bundle's Info.plist; "0.0.0" outside a bundle
    /// (tests, `swift run`).
    public static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
