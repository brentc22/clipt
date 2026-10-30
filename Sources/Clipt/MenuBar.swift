import AppKit
import Combine
import CliptCore

/// The status item and its menu.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private static var shared: MenuBar?

    static func install() {
        guard shared == nil else { return }
        shared = MenuBar()
    }

    /// Called by Settings after "Show menu bar icon" changes.
    static func refreshVisibility() { shared?.item.isVisible = Prefs.shared.showMenuBarIcon }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let openItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private var cancellable: AnyCancellable?

    private override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false

        openItem.title = "Open Clipt"
        openItem.target = self
        openItem.action = #selector(openPanel)
        menu.addItem(openItem)

        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        // Task 11 wires the updater; until then the item is present but disabled.
        let updates = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
        updates.isEnabled = false
        menu.addItem(updates)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clipt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        item.isVisible = Prefs.shared.showMenuBarIcon
        cancellable = History.shared.$captureState.sink { [weak self] state in
            self?.item.button?.image = Self.icon(paused: state != .active)
        }
        refreshItems()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) { refreshItems() }

    private func refreshItems() {
        let combo = Prefs.shared.hotKey
        openItem.keyEquivalent = combo.keyEquivalent
        openItem.keyEquivalentModifierMask = combo.modifiers
        pauseItem.title = Prefs.shared.capturePaused ? "Resume Capture" : "Pause Capture"
    }

    @objc private func openPanel() { PanelController.shared.show() }

    @objc private func togglePause() {
        Prefs.shared.capturePaused.toggle()
        History.shared.refreshCaptureState()
        refreshItems()
    }

    @objc private func clearHistory() { Self.confirmClearHistory() }

    @objc private func openSettings() { SettingsWindow.show() }

    /// Shared with Settings. Pinned items survive.
    static func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history? Pinned items are kept."
        alert.alertStyle = .warning
        let clear = alert.addButton(withTitle: "Clear History")
        let cancel = alert.addButton(withTitle: "Cancel")
        // Return must never clear: Cancel is the default, Escape also cancels.
        clear.hasDestructiveAction = true
        clear.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn { History.shared.clearHistory() }
    }

    // MARK: Icon

    /// `list.clipboard`, with a `pause.circle.fill` badge while capture is not active.
    /// Drawn into one template image so the menu bar tints it for light and dark; the
    /// badge sits in a gap cut out of the glyph so it stays readable.
    static func icon(paused: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let base = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipt")?
            .withSymbolConfiguration(config) else { return nil }
        guard paused else { base.isTemplate = true; return base }
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        guard let badge = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Capture paused")?
            .withSymbolConfiguration(badgeConfig) else { return base }

        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let b = badge.size
            let badgeRect = NSRect(x: rect.maxX - b.width, y: rect.minY, width: b.width, height: b.height)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipt, capture paused"
        return image
    }
}
