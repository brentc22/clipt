import AppKit
import ApplicationServices
import CliptCore

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

    /// For display: allowed, not decided yet, or denied.
    static var pasteboardStatus: PasteboardAccessStatus {
        PasteboardAccess.status(PasteboardBehavior(NSPasteboard.general.accessBehavior))
    }

    /// The deliberate, user-initiated way to raise macOS's one-time "Paste from Other Apps"
    /// alert: one programmatic read of the general pasteboard. Off the main thread, since
    /// the read waits on the alert; `done` runs on the main actor afterwards.
    static func askForPasteboardAccess(done: @escaping @MainActor () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let pasteboard = NSPasteboard.general
            if let item = pasteboard.pasteboardItems?.first, let type = item.types.first {
                _ = item.data(forType: type)
            } else {
                _ = pasteboard.string(forType: .string)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }
}
