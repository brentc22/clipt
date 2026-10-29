import AppKit
import ApplicationServices
import CliptCore

/// Writes a history item back to the pasteboard and, when it can, pastes it into the previous app.
@MainActor
enum Paster {
    static let copiedMessage = "Copied — press ⌘V to paste"
    private static let accessibilityPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static func paste(itemID: Int64, plainText: Bool, into target: NSRunningApplication?) async {
        let all = await History.shared.representations(of: itemID)
        let reps = PastePlan.representations(all, plainText: plainText)
        guard !reps.isEmpty else {
            Toast.show("Couldn't paste — the item is no longer available", symbol: "exclamationmark.triangle")
            return
        }

        // Decide before writing: the target may quit while we wait for the store.
        let route = PastePlan.route(hasAccessibility: AXIsProcessTrusted(),
                                    targetPID: target?.processIdentifier,
                                    targetIsRunning: target.map { !$0.isTerminated } ?? false,
                                    ownPID: ProcessInfo.processInfo.processIdentifier)
        guard write(reps, itemID: itemID) else {
            Toast.show("Couldn't paste", symbol: "exclamationmark.triangle")
            return
        }

        switch route {
        case .synthesizeCommandV:
            guard let target else { return }
            if await bringToFront(target) { postCommandV() }
            else { Toast.show(copiedMessage) }
        case .copyOnly(.noAccessibility):
            Toast.show(copiedMessage, action: ("Turn on auto-paste…", {
                if let url = URL(string: accessibilityPane) { NSWorkspace.shared.open(url) }
            }))
        case .copyOnly(.noTargetApp):
            Toast.show(copiedMessage)
        }
    }

    private static func write(_ reps: [Representation], itemID: Int64) -> Bool {
        let item = NSPasteboardItem()
        for rep in reps { item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type)) }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.writeObjects([item]) else { return false }
        // Same main-actor turn as the write, so the monitor cannot tick in between.
        History.shared.didWriteOwn(changeCount: pb.changeCount, itemID: itemID)
        return true
    }

    /// Activates the target and waits up to 300 ms for it to become frontmost.
    private static func bringToFront(_ app: NSRunningApplication) async -> Bool {
        app.activate()
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private static func postCommandV() {
        // Private state: physically held ⌥ or ⇧ (from ⌥↩) must not leak into the event.
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
