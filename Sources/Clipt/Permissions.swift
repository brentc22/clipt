import AppKit
import ApplicationServices

/// The two system permissions Clipt cares about, read live.
@MainActor
enum Permissions {
    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to prompt, then opens the Accessibility pane.
    static func requestAccessibility() {
        // The literal is the value of kAXTrustedCheckOptionPrompt (a C global, not concurrency-safe in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(accessibilityPane)
    }

    /// Same rule capture uses, so the two can never disagree.
    static var pasteboardAllowed: Bool { PasteboardMonitor.allows(NSPasteboard.general.accessBehavior) }
}
