import AppKit
import Combine
import ServiceManagement
import SwiftUI
import CliptCore

/// One standard titled window, reused while open.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var model: SettingsModel?

    static func show() {
        if window == nil {
            let model = SettingsModel()
            self.model = model
            let host = NSHostingController(rootView: SettingsView(model: model, panel: PanelController.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Clipt Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 480, height: 640))
            w.center()
            window = w
        }
        model?.hotKeyNote = nil
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The settings, mirrored from `Prefs` so SwiftUI can observe them. Every change is written
/// straight back.
@MainActor
final class SettingsModel: ObservableObject {
    static let repositoryURL = URL(string: "https://github.com/brentc22/clipt")!

    @Published var hotKey = Prefs.shared.hotKey
    @Published var hotKeyNote: String?
    @Published var launchAtLogin = false
    @Published var launchNote: String?
    @Published var showMenuBarIcon = Prefs.shared.showMenuBarIcon {
        didSet { Prefs.shared.showMenuBarIcon = showMenuBarIcon; MenuBar.refreshVisibility() }
    }
    @Published var motionEnabled = Prefs.shared.motionEnabled {
        didSet { Prefs.shared.motionEnabled = motionEnabled }
    }
    @Published var maxItems = Prefs.shared.retention.maxItems {
        didSet { saveRetention() }
    }
    @Published var maxAge = Prefs.shared.retention.maxAge {
        didSet { saveRetention() }
    }
    @Published var ignoredApps = Prefs.shared.ignoredApps
    @Published var selectedApp: String?

    init() { refreshLaunchAtLogin() }

    private func saveRetention() {
        let policy = RetentionPolicy(maxItems: maxItems, maxAge: maxAge)
        guard policy != Prefs.shared.retention else { return }
        Prefs.shared.retention = policy
        History.shared.applyRetention()
    }

    // MARK: Shortcut

    func recorded(_ combo: HotKeys.Combo?) {
        // Clearing is not offered: Clipt always has a shortcut.
        guard let combo, combo != Prefs.shared.hotKey else { return }
        let previous = Prefs.shared.hotKey
        Prefs.shared.hotKey = combo   // the controller re-registers synchronously
        // A failed remap is put back quietly, so read the truth again.
        hotKey = Prefs.shared.hotKey
        hotKeyNote = hotKey == combo ? nil : "\(combo.symbol) is used by another app. Kept \(previous.symbol)."
    }

    var hotKeyWarning: String? {
        hotKey == Prefs.defaultHotKey ? "Also used by Safari and Chrome to inspect elements" : nil
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: launchAtLogin = true; launchNote = nil
        case .requiresApproval:
            launchAtLogin = true
            launchNote = "Approve Clipt in System Settings → General → Login Items."
        case .notRegistered: launchAtLogin = false; launchNote = nil
        case .notFound:
            launchAtLogin = false
            launchNote = "Launch at login needs Clipt to run from an installed app bundle."
        @unknown default: launchAtLogin = false
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            launchNote = "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    // MARK: Ignored apps

    func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard !ignoredApps.contains(id) else { selectedApp = id; return }
        ignoredApps.append(id)
        selectedApp = id
        Prefs.shared.ignoredApps = ignoredApps
    }

    func removeSelectedApp() {
        guard let id = selectedApp else { return }
        ignoredApps.removeAll { $0 == id }
        selectedApp = nil
        Prefs.shared.ignoredApps = ignoredApps
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var panel: PanelController
    @ObservedObject private var updater = Updater.shared

    private static let itemLabels: [Int?: String] = [200: "200 items", 1000: "1,000 items", 5000: "5,000 items", nil: "Unlimited"]
    private static let ageLabels: [TimeInterval?: String] = [86_400: "1 day", 604_800: "7 days", 2_592_000: "30 days", nil: "Never"]

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(combo: model.hotKey) { model.recorded($0) }
                }
                if let note = model.hotKeyNote ?? (panel.hotKeyRegistered ? nil : "This shortcut is used by another app") {
                    caption(note, warning: true)
                } else if let warning = model.hotKeyWarning {
                    caption(warning, warning: true)
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let note = model.launchNote { caption(note, warning: true) }
                Toggle("Show menu bar icon", isOn: $model.showMenuBarIcon)
                Toggle("Animations", isOn: $model.motionEnabled)
            }
            Section("History") {
                Picker("Keep", selection: $model.maxItems) {
                    ForEach(RetentionPolicy.itemOptions, id: \.self) { Text(Self.itemLabels[$0] ?? "").tag($0) }
                }
                Picker("Delete items older than", selection: $model.maxAge) {
                    ForEach(RetentionPolicy.ageOptions, id: \.self) { Text(Self.ageLabels[$0] ?? "").tag($0) }
                }
                Button("Clear History…", role: .destructive) { MenuBar.confirmClearHistory() }
            }
            Section("Privacy") {
                List(model.ignoredApps, id: \.self, selection: $model.selectedApp) { id in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(SettingsModel.appName(id))
                        if SettingsModel.appName(id) != id {
                            Text(id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 110)
                HStack(spacing: 6) {
                    Button { model.addApp() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add app")
                    Button { model.removeSelectedApp() } label: { Image(systemName: "minus") }
                        .accessibilityLabel("Remove selected app")
                        .disabled(model.selectedApp == nil)
                    Spacer()
                    Text("Ignored apps").font(.caption).foregroundStyle(.secondary)
                }
                caption("Passwords copied from password managers are never saved.", warning: false)
            }
            Section("About") {
                LabeledContent("Version", value: CliptVersion.current)
                Link("GitHub", destination: SettingsModel.repositoryURL)
                Toggle("Look for new versions every day", isOn: $updater.automaticallyChecks)
                LabeledContent {
                    if let version = updater.available?.version {
                        Button("Install Clipt \(version.description)…") { updater.offerAvailable() }
                    } else {
                        Button("Check Now") { updater.check(userInitiated: true) }.disabled(updater.isBusy)
                    }
                } label: {
                    Text(Self.updateStatus(updater)).foregroundStyle(.secondary)
                }
                caption("Asks GitHub whether there's a newer Clipt. Nothing about you or your clipboard is sent.", warning: false)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: panel.hotKeyRegistered) { _, registered in
            if registered { model.hotKeyNote = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLogin()
        }
    }

    /// "Checked today at 15:42", or the version that is waiting.
    private static func updateStatus(_ updater: Updater) -> String {
        if updater.isBusy { return "Checking…" }
        if let version = updater.available?.version { return "Clipt \(version) is out" }
        guard let last = updater.lastCheck else { return "Not checked yet" }
        let formatter = DateFormatter()
        formatter.locale = PanelFormat.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return "Checked \(formatter.string(from: last))"
    }

    private func caption(_ text: String, warning: Bool) -> some View {
        Text(text).font(.caption).foregroundStyle(warning ? Color.orange : Color.secondary)
    }
}
