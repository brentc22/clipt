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
    private var reading = false

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

    /// `.default` means the user has not decided yet: macOS will ask on Clipt's first
    /// programmatic read, and only after that alert is Clipt listed in "Paste from Other
    /// Apps". Capture still runs (see `PasteboardAccess.capturesAllowed`).
    static func allows(_ behavior: NSPasteboard.AccessBehavior) -> Bool {
        PasteboardAccess.capturesAllowed(PasteboardBehavior(behavior))
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
        guard changed, !reading else { return }
        lastChangeCount = count
        guard state == .active, let history else { return }

        if let id = history.claimOwnWrite(changeCount: count) {
            history.touch(id)
            return
        }

        // Type names first (all items, not just the first); content only if they pass.
        let items = pasteboard.pasteboardItems ?? []
        let types = Array(Set(items.flatMap { $0.types.map(\.rawValue) }))
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        if CaptureFilter.shouldSkip(types: types, sourceBundleID: bundleID, ignoredApps: Set(Prefs.shared.ignoredApps)) {
            return
        }

        // Content is read off the main thread: data(forType:) can block on the source app
        // (promised data) and can be tens of MB. NSPasteboard's thread safety is not
        // documented, so the reads share one dedicated serial queue, and the monitor reads
        // nothing from the pasteboard while one is in flight (the next tick catches up).
        reading = true
        let appName = app?.localizedName
        Self.readQueue.async { [weak self] in
            let reps = Self.readRepresentations(expecting: count)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    guard let reps, let history = self.history else { return }
                    history.capture(PasteboardSnapshot(representations: reps), sourceBundleID: bundleID, sourceAppName: appName)
                }
            }
        }
    }

    private static let readQueue = DispatchQueue(label: "com.brentc22.Clipt.pasteboard-read", qos: .userInitiated)

    /// Types Clipt understands first, then the rest while the running total stays under the
    /// cap. Nil if the pasteboard changed meanwhile (the next tick has the newer copy).
    nonisolated private static func readRepresentations(expecting count: Int) -> [Representation]? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == count else { return nil }
        let items = pasteboard.pasteboardItems ?? []
        var reps: [Representation] = []
        var total = 0
        if let first = items.first {
            let names = first.types.filter { !$0.rawValue.hasPrefix("dyn.") }
            let understood = names.filter { PasteType.understood.contains($0.rawValue) }
            let others = names.filter { !PasteType.understood.contains($0.rawValue) }
            for type in understood {
                if let data = first.data(forType: type) { reps.append(Representation(type: type.rawValue, data: data)); total += data.count }
            }
            for type in others where total < ClipClassifier.sizeCap {
                if let data = first.data(forType: type) { reps.append(Representation(type: type.rawValue, data: data)); total += data.count }
            }
        }
        // Several files are several pasteboard items; keep each one's file URL.
        for item in items.dropFirst() {
            if let data = item.data(forType: NSPasteboard.PasteboardType(PasteType.fileURL)) {
                reps.append(Representation(type: PasteType.fileURL, data: data))
            }
        }
        guard pasteboard.changeCount == count, !reps.isEmpty else { return nil }
        return reps
    }
}

extension PasteboardBehavior {
    init(_ behavior: NSPasteboard.AccessBehavior) {
        switch behavior {
        case .default: self = .notDecided
        case .ask: self = .ask
        case .alwaysAllow: self = .alwaysAllow
        case .alwaysDeny: self = .alwaysDeny
        @unknown default: self = .unknown
        }
    }
}
