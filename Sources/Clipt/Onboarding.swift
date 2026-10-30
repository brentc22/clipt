import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The three-step welcome window: one titled window, reused while open.
@MainActor
enum Onboarding {
    private static var window: NSWindow?
    private static var model: OnboardingModel?
    private static let closer = WindowCloser()

    static var isShowing: Bool { window?.isVisible ?? false }

    static func show(step: Int = 0) {
        if window == nil {
            let model = OnboardingModel()
            self.model = model
            let host = NSHostingController(rootView: OnboardingView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Clipt"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = closer
            w.setContentSize(NSSize(width: 520, height: 420))
            w.center()
            window = w
        }
        model?.goTo(step)
        model?.startPolling()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    fileprivate static func close() { window?.close() }

    fileprivate static func windowClosed() {
        model?.stopPolling()
        Prefs.shared.onboardingDone = true   // skipping, finishing and closing all count
    }

    private final class WindowCloser: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated { Onboarding.windowClosed() }
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    static let stepCount = 3

    @Published var step = 0
    @Published var accessibility = Permissions.accessibilityGranted
    @Published var pasteboard = Permissions.pasteboardAllowed
    @Published var launchAtLogin: Bool
    /// Reuses the shortcut and launch-at-login handling from Settings.
    let settings = SettingsModel()

    init() {
        // On by default for a first run; if login launch is already on, show the real state.
        settings.refreshLaunchAtLogin()
        launchAtLogin = SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound
            ? true : settings.launchAtLogin
    }
    private var timer: Timer?

    func goTo(_ step: Int) { self.step = min(max(step, 0), Self.stepCount - 1) }

    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let a = Permissions.accessibilityGranted
        if a != accessibility { accessibility = a }
        let p = Permissions.pasteboardAllowed
        if p != pasteboard { pasteboard = p }
        History.shared.refreshCaptureState()   // lifts the paused banner as soon as access is allowed
    }

    func finish() {
        settings.refreshLaunchAtLogin()
        if launchAtLogin != settings.launchAtLogin {
            settings.setLaunchAtLogin(launchAtLogin)
            // The window is about to close, so a failure has to surface elsewhere.
            if let note = settings.launchNote { Toast.show(note, symbol: "exclamationmark.triangle") }
        }
        Onboarding.close()
    }

    func skip() { Onboarding.close() }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var panel = PanelController.shared

    private var last: Bool { model.step == OnboardingModel.stepCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: accessibilityStep
                case 1: pasteboardStep
                default: shortcutStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 28)

            HStack {
                Button("Skip") { model.skip() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.step + 1) of \(OnboardingModel.stepCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Back") { model.goTo(model.step - 1) }
                    .disabled(model.step == 0)
                if last {
                    Button("Start using Clipt") { model.finish() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { model.goTo(model.step + 1) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
        .background { Rectangle().fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: 0)).ignoresSafeArea() }
    }

    // MARK: Steps

    private var accessibilityStep: some View {
        stepLayout(symbol: "keyboard", title: "Paste with one keystroke",
                   body: "Clipt pastes into the app you were using. macOS asks you to allow this under Accessibility.") {
            Button("Allow Accessibility…") { Permissions.requestAccessibility() }
            status(model.accessibility, on: "Accessibility is allowed", off: "Accessibility is not allowed yet")
        }
    }

    private var pasteboardStep: some View {
        stepLayout(symbol: "doc.on.clipboard", title: "Let Clipt see what you copy",
                   body: "Open System Settings → Privacy & Security → Paste from Other Apps, find Clipt and choose Allow.") {
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Open System Settings")
                Text("2. Go to Privacy & Security → Paste from Other Apps")
                Text("3. Find Clipt and choose Allow")
            }
            .font(.callout).foregroundStyle(.secondary)
            Button("Open System Settings") {
                // There is no deep link to this setting, so open the app's root.
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
            status(model.pasteboard, on: "Clipt can see what you copy", off: "Not allowed yet — Clipt is not saving new copies")
        }
    }

    private var shortcutStep: some View {
        stepLayout(symbol: "command", title: "Your shortcut",
                   body: "Press this anywhere to open your clipboard history. Click it to choose another.") {
            ShortcutRecorder(combo: model.settings.hotKey) { model.settings.recorded($0) }
            if let note = model.settings.hotKeyNote ?? (panel.hotKeyRegistered ? nil : "This shortcut is used by another app") {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
            Toggle("Launch Clipt at login", isOn: $model.launchAtLogin)
        }
    }

    private func stepLayout<Content: View>(symbol: String, title: String, body: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold())
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
            Spacer(minLength: 0)
        }
    }

    private func status(_ ok: Bool, on: String, off: String) -> some View {
        Label(ok ? on : off, systemImage: ok ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(ok ? Color.green : Color.secondary)
            .font(.callout)
    }
}
