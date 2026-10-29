import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "com.brentc22.Clipt"

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: hand over to the running copy and leave.
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != me }
        if let other = others.first {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipt")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Clipt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        History.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        History.shared.stop()
    }
}
