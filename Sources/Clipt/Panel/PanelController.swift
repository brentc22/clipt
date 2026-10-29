import AppKit
import SwiftUI
import CliptCore

/// Owns the one panel. It is built at launch and only ever ordered in and out, so the
/// hotkey press does no allocation or layout work.
@MainActor
final class PanelController {
    static let shared = PanelController()

    /// The app that was frontmost when the panel opened (never Clipt itself); Task 7 pastes into it.
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

    private func registerHotKey() {
        hotKeys.unregisterAll()
        let combo = Prefs.shared.hotKey
        if !hotKeys.register(combo, { [weak self] in self?.toggle() }) {
            NSLog("Clipt: hotkey %@ is taken by another app", combo.symbol)
        }
    }

    func toggle() { isVisible ? hide(animated: false) : show() }

    func show() {
        guard let panel else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { pasteTarget = front }
        let screens = NSScreen.screens.map(\.visibleFrame)
        panel.setFrame(PanelPlacement.frame(screens: screens, mouse: NSEvent.mouseLocation), display: false)
        panel.makeKeyAndOrderFront(nil)
        // Task 7: reset search and selection here.
    }

    func hide(animated: Bool) {
        guard let panel, panel.isVisible else { return }
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
