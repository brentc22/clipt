import AppKit
import CliptCore
import os

/// Polls the general pasteboard's change count (the only cheap signal macOS offers) and
/// hands new, allowed copies to History. Nothing is read while capture is not active.
@MainActor
final class PasteboardMonitor {
    private static let log = Logger(subsystem: "com.brentc22.Clipt", category: "monitor")

    private weak var history: History?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastStateCheck = Date.distantPast
    private var state: CaptureState = .active

    init(history: History) { self.history = history }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Self.log.info("started, accessBehavior \(String(describing: NSPasteboard.general.accessBehavior), privacy: .public)")
        refreshState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-evaluates the gate now (the user toggled pause, or came back from Settings).
    func refreshState() {
        lastStateCheck = Date()
        let pasteboard = NSPasteboard.general
        let behavior = pasteboard.accessBehavior
        let allowed = Self.allows(behavior)
        let new = CaptureGate.state(userPaused: Prefs.shared.capturePaused, accessAllowed: allowed)
        if new != state {
            Self.log.info("capture state \(String(describing: new), privacy: .public), accessBehavior \(String(describing: behavior), privacy: .public)")
        }
        state = new
        history?.setCaptureState(new)
    }

    /// `.default` counts as allowed: it is what the system reports when the privacy
    /// feature is off. Only an explicit ask/deny blocks.
    static func allows(_ behavior: NSPasteboard.AccessBehavior) -> Bool {
        switch behavior {
        case .alwaysAllow, .default: true
        case .ask, .alwaysDeny: false
        @unknown default: false
        }
    }

    private func tick() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        let changed = count != lastChangeCount
        // While not active, re-check every 2 s so the state clears by itself once the
        // user allows access (or un-pauses).
        if changed || (state != .active && Date().timeIntervalSince(lastStateCheck) >= 2) {
            refreshState()
        }
        guard changed else { return }
        lastChangeCount = count
        guard state == .active, let history else { return }

        if let id = history.claimOwnWrite(changeCount: count) {
            history.touch(id)
            return
        }

        // Type names first; content only if they pass.
        let items = pasteboard.pasteboardItems ?? []
        let types = items.first?.types.map(\.rawValue) ?? []
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        if CaptureFilter.shouldSkip(types: types, sourceBundleID: bundleID, ignoredApps: Set(Prefs.shared.ignoredApps)) {
            return
        }

        var reps: [Representation] = []
        if let first = items.first {
            for type in first.types where !type.rawValue.hasPrefix("dyn.") {
                if let data = first.data(forType: type) { reps.append(Representation(type: type.rawValue, data: data)) }
            }
        }
        // Several files are several pasteboard items; keep each one's file URL.
        for item in items.dropFirst() {
            if let data = item.data(forType: NSPasteboard.PasteboardType(PasteType.fileURL)) {
                reps.append(Representation(type: PasteType.fileURL, data: data))
            }
        }
        // The pasteboard changed while we were reading: drop this one, the next tick has the newer copy.
        guard pasteboard.changeCount == count, !reps.isEmpty else { return }

        history.capture(PasteboardSnapshot(representations: reps), sourceBundleID: bundleID, sourceAppName: app?.localizedName)
    }
}
