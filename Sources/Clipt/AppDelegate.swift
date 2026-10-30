import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "com.brentc22.Clipt"

    static let reopenNotification = Notification.Name("com.brentc22.Clipt.reopen")

    /// With the menu bar icon hidden, reopening the app is the only way back to Settings.
    static func openSettingsIfIconHidden() {
        if !Prefs.shared.showMenuBarIcon { SettingsWindow.show() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: hand over to the running copy and leave.
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != me }
        if let other = others.first {
            other.activate()
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        MenuBar.install()
        DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.openSettingsIfIconHidden() }
        }

        History.shared.start()
        PanelController.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettingsIfIconHidden()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        History.shared.stop()
    }
}
