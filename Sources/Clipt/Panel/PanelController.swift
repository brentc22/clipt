import AppKit
import SwiftUI
import Combine
import CliptCore

/// Owns the one panel. It is built at launch and only ever ordered in and out, so the
/// hotkey press does no allocation or layout work.
@MainActor
final class PanelController: ObservableObject {
    static let shared = PanelController()

    /// The app that was frontmost when the panel opened (never Clipt itself); Task 7 pastes into it.
    /// False when the stored shortcut could not be registered (taken by another app).
    @Published private(set) var hotKeyRegistered = false
    private var registeredCombo: HotKeys.Combo?

    private(set) var pasteTarget: NSRunningApplication?

    private var panel: PanelWindow?
    let model = PanelModel()
    /// Clear room around the glass for its shadow; the panel itself stays `PanelPlacement.size`.
    static let shadowMargin: CGFloat = 40
    private let hotKeys = HotKeys()
    private var observers: [NSObjectProtocol] = []

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The close animation is running; the panel is still on screen but on its way out.
    private var isClosing = false
    /// Bumped by every close and every show, so a close animation that ends late can tell
    /// it was overtaken and must not order the panel out.
    private var closeToken = 0
    /// Run once the panel is off screen: the paste waiting on the close.
    private var afterClose: [() -> Void] = []

    /// Build the window, register the hotkey. Call once at launch.
    func start() {
        guard panel == nil else { return }
        let panel = PanelWindow()
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.model.escape() { self.hide(animated: true) }
        }
        model.pasteTarget = { [weak self] in self?.pasteTarget }
        model.close = { [weak self] in self?.hide(animated: true) }
        model.isClosing = { [weak self] in self?.isClosing ?? false }
        model.closeForPaste = { [weak self] then in
            if let self { self.hideForPaste(then: then) } else { then() }
        }
        let m = Self.shadowMargin
        let container = NSView(frame: CGRect(origin: .zero, size: CGSize(width: PanelPlacement.size.width + 2 * m,
                                                                         height: PanelPlacement.size.height + 2 * m)))
        container.wantsLayer = true   // Motion animates this layer: scale and alpha, in the render server
        let host = NSHostingView(rootView: PanelView(model: model))
        host.frame = CGRect(origin: CGPoint(x: m, y: m), size: PanelPlacement.size)
        container.addSubview(host)
        panel.contentView = container
        panel.setContentSize(container.frame.size)
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        self.panel = panel
        // The first hotkey press should not be what loads the spring classes and the
        // accessibility setting: touch them now.
        Motion.prewarm()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            // Focus is already elsewhere, so the panel can take its time leaving.
            MainActor.assumeIsolated { self?.hide(animated: true) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.hide(animated: true) }
            }
        })
        observers.append(nc.addObserver(forName: Prefs.hotKeyDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        })
        registerHotKey()
    }

    /// On failure the previous combo is registered again and written back to Prefs, so the
    /// user keeps a working shortcut and Settings can show why the remap did not take.
    private func registerHotKey() {
        hotKeys.unregisterAll()
        let wanted = Prefs.shared.hotKey
        let action: @MainActor @Sendable () -> Void = { [weak self] in self?.toggle() }
        if hotKeys.register(wanted, action) {
            registeredCombo = wanted
            hotKeyRegistered = true
            return
        }
        Toast.show("Shortcut \(wanted.symbol) is already in use", symbol: "exclamationmark.triangle")
        if let previous = registeredCombo, previous != wanted, hotKeys.register(previous, action) {
            Prefs.shared.restoreHotKey(previous)
            hotKeyRegistered = true
        } else {
            registeredCombo = nil
            hotKeyRegistered = false
        }
    }

    /// While a paste is closing the panel, the hotkey waits: reopening would take the ⌘V.
    func toggle() {
        if isClosing {
            if afterClose.isEmpty { show() }
            return
        }
        isVisible ? hide(animated: true) : show()
    }

    /// On screen in this same turn; the open animation runs on the content layer and never delays it.
    func show() {
        guard let panel else { return }
        if isClosing {
            // Reopened mid-close: the open picks up from where the close got to.
            isClosing = false
            closeToken += 1
            panel.ignoresMouseEvents = false
        }
        // Never a stale target: nil unless a real non-Clipt app is frontmost.
        let front = NSWorkspace.shared.frontmostApplication
        pasteTarget = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let screens = NSScreen.screens.map(\.visibleFrame)
        let frame = PanelPlacement.frame(screens: screens, mouse: NSEvent.mouseLocation)
        if !panel.isVisible {
            panel.setFrame(frame.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin), display: false)
        }
        model.willShow()
        Motion.open(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    /// `animated` false orders out at once (focus moved elsewhere, another app activated);
    /// it also cuts short a close that is already running.
    func hide(animated: Bool) {
        close(animated: animated, duration: nil)
    }

    /// The paste path: a quick close, and `then` runs once the panel is off screen — and with
    /// it keyboard focus is back in the target app — or `PanelMotion.pasteHandoff` after the
    /// close began, whichever comes first. The ⌘V never waits out the whole animation.
    func hideForPaste(then: @escaping () -> Void) {
        guard let panel, panel.isVisible else { return then() }
        afterClose.append(then)
        close(animated: true, duration: PanelMotion.pasteCloseDuration)
        let token = closeToken
        // The fade is done at `pasteCloseDuration`; waiting for Core Animation's completion on top
        // of that costs another frame or two, so the deadline is whichever of the two is sooner.
        let deadline = min(PanelMotion.pasteCloseDuration, PanelMotion.pasteHandoff)
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
            MainActor.assumeIsolated {
                // Still on screen at the deadline: finish now, so focus is back before the ⌘V.
                guard let self, self.isClosing, self.closeToken == token else { return }
                self.finishClose()
            }
        }
    }

    private func close(animated: Bool, duration: TimeInterval?) {
        // Callers that paste read pasteTarget first: it is cleared here.
        guard let panel, panel.isVisible else { return }
        pasteTarget = nil
        if isClosing {
            if !animated { finishClose() }
            return
        }
        guard animated else { return finishClose() }
        isClosing = true
        closeToken += 1
        let token = closeToken
        // On its way out it takes no clicks; keys still reach it until orderOut, and the model ignores a second paste.
        panel.ignoresMouseEvents = true
        Motion.close(panel, duration: duration) { [weak self] in
            guard let self, self.isClosing, self.closeToken == token else { return }   // overtaken by a show
            self.finishClose()
        }
    }

    private func finishClose() {
        guard let panel else { return }
        isClosing = false
        closeToken += 1
        pasteTarget = nil
        panel.orderOut(nil)
        Motion.reset(panel)   // after orderOut, so the full-alpha model value is never on screen
        panel.ignoresMouseEvents = false
        model.didHide()
        let waiting = afterClose
        afterClose = []
        for run in waiting { run() }
    }
}
