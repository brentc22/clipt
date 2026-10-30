import AppKit
import SwiftUI
import CliptCore

/// A small Liquid Glass HUD near the bottom-center of the active screen.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    /// `action` adds a button; the toast then stays a little longer so it can be reached.
    static func show(_ message: String, symbol: String = "doc.on.clipboard", action: (title: String, run: @MainActor () -> Void)? = nil) {
        generation += 1
        let mine = generation
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message, symbol: symbol, actionTitle: action?.title) {
            action?.run()
            if mine == generation { dismiss() }
        })
        let size = hosting.fittingSize
        let pad: CGFloat = 20   // room for the glass shadow
        let screen = activeScreen().visibleFrame
        let frame = CGRect(x: screen.midX - size.width / 2 - pad, y: screen.minY + screen.height * 0.12 - pad,
                           width: size.width + 2 * pad, height: size.height + 2 * pad)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.sharingType = .none
        p.ignoresMouseEvents = action == nil
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting.frame = CGRect(x: pad, y: pad, width: size.width, height: size.height)
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.addSubview(hosting)
        p.contentView = container
        let style = Motion.style
        // Animations first, then on screen: the first frame shown is the first frame of the pop.
        Motion.present(p, from: style.moves ? 0.9 : 1, spring: .pop, fade: style.moves ? 0.15 : MotionStyle.fadeDuration)
        p.orderFrontRegardless()
        panel = p

        let lifetime: Double = action == nil ? 2.5 : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            if mine == generation { dismiss() }
        }
    }

    private static func dismiss() {
        guard let p = panel else { return }
        panel = nil
        let style = Motion.style
        Motion.dismiss(p, to: style.moves ? 0.96 : 1, duration: style.moves ? 0.22 : MotionStyle.fadeDuration) {
            p.orderOut(nil)
        }
    }

    private static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            Text(message).font(.system(size: 14, weight: .medium))
            if let actionTitle {
                Button(actionTitle, action: onAction).buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }
}
