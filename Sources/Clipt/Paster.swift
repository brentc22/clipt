import AppKit
import ApplicationServices
import CliptCore

/// Writes a history item back to the pasteboard and, when it can, pastes it into the previous app.
@MainActor
enum Paster {
    static let copiedMessage = "Copied — press ⌘V to paste"

    static func paste(itemID: Int64, kind: ClipKind, plainText: Bool, into target: NSRunningApplication?) async {
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
                                    ownPID: ProcessInfo.processInfo.processIdentifier,
                                    targetBundleID: target?.bundleIdentifier,
                                    kind: PastePlan.pasteKind(kind, writing: reps))
        guard write(reps, to: .general, itemID: itemID) else {
            Toast.show("Couldn't paste", symbol: "exclamationmark.triangle")
            return
        }

        switch route {
        case .synthesizeCommandV:
            guard let target else { return }
            if await bringToFront(target) { postCommandV() }
            else { Toast.show(copiedMessage) }
        case .copyOnly(.noAccessibility):
            Toast.show(copiedMessage, action: ("Turn on auto-paste…", { Onboarding.show(step: 0) }))
        case .copyOnly(.noTargetApp):
            Toast.show(copiedMessage)
        }
    }

    /// One pasteboard item per file (see `PastePlan.pasteboardItems`), in one write.
    /// `itemID` nil writes without claiming it as Clipt's own (probes on a private pasteboard).
    static func write(_ reps: [Representation], to pb: NSPasteboard, itemID: Int64?) -> Bool {
        let items = PastePlan.pasteboardItems(reps).map { group in
            let item = NSPasteboardItem()
            for rep in group { item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type)) }
            return item
        }
        pb.clearContents()
        guard pb.writeObjects(items) else { return false }
        // Same main-actor turn as the write, so the monitor cannot tick in between.
        if let itemID { History.shared.didWriteOwn(changeCount: pb.changeCount, itemID: itemID) }
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
