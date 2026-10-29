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
    private let hotKeys = HotKeys()
    private var observers: [NSObjectProtocol] = []

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Build the window, register the hotkey. Call once at launch.
    func start() {
        guard panel == nil else { return }
        let panel = PanelWindow()
        panel.onCancel = { [weak self] in self?.hide(animated: false) }
        let host = NSHostingView(rootView: PanelPlaceholder())
        host.frame = CGRect(origin: .zero, size: PanelPlacement.size)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        self.panel = panel

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(animated: false) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.hide(animated: false) }
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

    func toggle() { isVisible ? hide(animated: false) : show() }

    func show() {
        guard let panel else { return }
        // Never a stale target: nil unless a real non-Clipt app is frontmost.
        let front = NSWorkspace.shared.frontmostApplication
        pasteTarget = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let screens = NSScreen.screens.map(\.visibleFrame)
        panel.setFrame(PanelPlacement.frame(screens: screens, mouse: NSEvent.mouseLocation), display: false)
        panel.makeKeyAndOrderFront(nil)
        // Task 7: reset search and selection here.
    }

    func hide(animated: Bool) {
        // Task 7 reads pasteTarget before calling hide when pasting.
        guard let panel, panel.isVisible else { return }
        pasteTarget = nil
        panel.orderOut(nil)
    }
}

/// Stands in until Task 7 supplies the real list.
private struct PanelPlaceholder: View {
    var body: some View {
        Text("Clipt")
            .font(.title)
            .frame(width: PanelPlacement.size.width, height: PanelPlacement.size.height)
            .glassEffect(in: .rect(cornerRadius: 22))
    }
}
