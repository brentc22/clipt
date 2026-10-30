import AppKit
import QuartzCore
import SwiftUI
import CliptCore

/// Every animation in Clipt takes its timing from here, so the app moves as one thing: real
/// springs, the way macOS's own chrome moves — windows on `CASpringAnimation` in the render
/// server, views on SwiftUI springs that retarget instead of queueing. With Reduce Motion on,
/// or motion off in Settings, movement becomes a plain fade (`MotionStyle` decides).
@MainActor
enum Motion {
    static var style: MotionStyle {
        MotionStyle(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    motionEnabled: Prefs.shared.motionEnabled)
    }
    static var reduced: Bool { !style.moves }


    /// A spring in SwiftUI's terms: `response` is roughly how long it takes, `bounce` 0 settles
    /// without overshoot, 0.2 lands with a visible little give.
    struct Spring {
        let response: Double
        let bounce: Double
        /// Moves that make room or come back: quick, no overshoot to distract.
        static let glide = Spring(response: 0.36, bounce: 0.04)
        /// Things arriving — the panel, a toast: lands with a hint of give.
        static let arrive = Spring(response: 0.46, bounce: 0.16)
        /// Pops in place (toast, paste pulse): a livelier scale.
        static let pop = Spring(response: 0.38, bounce: 0.3)
        /// Leaving: stiff, so it's gone before the eye follows.
        static let leave = Spring(response: 0.28, bounce: 0)
        /// The selection under a held arrow key: stiff enough to stay within a row of the key.
        static let follow = Spring(response: 0.12, bounce: 0)

        var animation: Animation { .spring(response: response, dampingFraction: 1 - bounce) }
        /// For keyframes.
        var swiftUI: SwiftUI.Spring { SwiftUI.Spring(response: response, dampingRatio: 1 - bounce) }
    }

    /// SwiftUI's version, for selections and list changes.
    static var spring: Animation {
        reduced ? .easeOut(duration: MotionStyle.fadeDuration) : Spring(response: 0.3, bounce: 0.12).animation
    }
    static var quick: Animation { .easeOut(duration: reduced ? MotionStyle.fadeDuration : 0.14) }

    /// The selection highlight's move. Each new target retargets the running spring (SwiftUI
    /// carries its velocity), so a held key never builds a queue; a repeat uses the stiff
    /// `follow` spring so it keeps up. Fades-only: a step crossfades, a repeat just jumps.
    static func selection(repeating: Bool) -> Animation? {
        if reduced { return repeating ? nil : .easeOut(duration: MotionStyle.fadeDuration) }
        return repeating ? Spring.follow.animation : spring
    }

    /// Loads what the first `open` would otherwise load on the hotkey press.
    static func prewarm() {
        _ = style
        _ = springAnimation("transform", from: nil, to: nil, .arrive)
    }

    // MARK: Windows

    /// Brings the panel in: window alpha 0 → 1 and, unless reduced, scale 0.96 → 1 on the
    /// `arrive` spring. Call right before ordering the window front, in the same turn, so the
    /// first frame on screen is already the first frame of the animation. Visibility never waits on it.
    static func open(_ panel: NSPanel) {
        let style = style
        present(panel, from: style.openScale, spring: .arrive, fade: style.openFadeDuration)
    }

    /// Takes the panel out — window alpha to 0 and, unless reduced, scale to 0.98 on the
    /// `leave` spring — then calls `completion`, which orders it out. Also called if the
    /// animation is cut short by a later `open`; the caller tells the two apart.
    static func close(_ panel: NSPanel, duration: TimeInterval? = nil, completion: @escaping @MainActor () -> Void) {
        let style = style
        dismiss(panel, to: style.closeScale, duration: duration ?? style.closeDuration, completion: completion)
    }

    /// The general form of `open`; the toast uses it with its own scale and spring. The fade is
    /// the window's `alphaValue`, composited by the window server, so Liquid Glass's backdrop
    /// fades as one piece; the scale is on the content layer, in the render server.
    static func present(_ window: NSWindow, from scale: Double, spring: Spring, fade: TimeInterval) {
        // Already on screen means a close is being interrupted: start from where it is, so nothing flickers.
        let interrupting = window.isVisible
        if !interrupting { window.alphaValue = 0 }
        WindowFade.run(window, to: 1, duration: fade, ease: .settle, completion: nil)

        guard let layer = contentLayer(window) else { return }
        let fromTransform = interrupting ? (layer.presentation()?.transform ?? CATransform3DIdentity) : scaled(layer, scale)
        layer.removeAllAnimations()
        guard scale != 1 || !CATransform3DIsIdentity(fromTransform) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(springAnimation("transform", from: NSValue(caTransform3D: fromTransform),
                                  to: NSValue(caTransform3D: CATransform3DIdentity), spring), forKey: "scale")
        CATransaction.commit()
    }

    /// The general form of `close`. `completion` runs when the fade ends, or when a later
    /// `present` takes over the fade; the caller tells the two apart.
    static func dismiss(_ window: NSWindow, to scale: Double, duration: TimeInterval,
                        completion: @escaping @MainActor () -> Void) {
        WindowFade.run(window, to: 0, duration: duration, ease: .exit, completion: completion)

        guard scale != 1, let layer = contentLayer(window) else { return }
        let fromTransform = layer.presentation()?.transform ?? CATransform3DIdentity
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shrink = springAnimation("transform", from: NSValue(caTransform3D: fromTransform),
                                     to: NSValue(caTransform3D: scaled(layer, scale)), .leave)
        // Once alpha is 0 the rest of the spring is invisible: cut it there.
        shrink.duration = duration
        hold(shrink)
        layer.add(shrink, forKey: "scale")
        CATransaction.commit()
    }

    /// Drops whatever `dismiss` left: the layer's held scale and a fade still stepping. Call
    /// after ordering the window out.
    static func reset(_ window: NSWindow) {
        WindowFade.stop(window)
        contentLayer(window)?.removeAllAnimations()
    }

    /// A `CASpringAnimation` from `from` to `to`; the caller sets the model value to `to`.
    /// Cut at the point where what's left of the spring is under a pixel, not its full tail.
    static func springAnimation(_ keyPath: String, from: Any?, to: Any?, _ spring: Spring) -> CASpringAnimation {
        let a = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce)
        a.keyPath = keyPath
        a.fromValue = from
        a.toValue = to
        a.duration = min(a.settlingDuration, spring.response * (1.6 + 3 * spring.bounce))
        return a
    }

    private static func hold(_ a: CAAnimation) {
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
    }

    private static func contentLayer(_ window: NSWindow) -> CALayer? {
        guard let view = window.contentView else { return nil }
        view.wantsLayer = true
        return view.layer
    }

    /// A scale around the layer's middle, whatever its anchor: AppKit owns a backing layer's
    /// anchor point, so the transform carries the offset instead of moving the anchor.
    private static func scaled(_ layer: CALayer, _ s: Double) -> CATransform3D {
        let b = layer.bounds
        var t = CATransform3DMakeScale(s, s, 1)
        t.m41 = b.width * (0.5 - layer.anchorPoint.x) * (1 - s)
        t.m42 = b.height * (0.5 - layer.anchorPoint.y) * (1 - s)
        return t
    }
}

/// One window's alpha fade, stepped on the display link along an `Ease` curve by elapsed time,
/// so a busy frame catches up instead of stretching the fade, and the end (and `completion`)
/// lands on time. AppKit's `animator().alphaValue` was not used: it sometimes skipped the fade
/// and completed at once, which ordered the panel out without a close animation.
@MainActor
private final class WindowFade: NSObject {
    static var running: [ObjectIdentifier: WindowFade] = [:]
    weak var window: NSWindow?
    let link: CADisplayLink
    let from: CGFloat, to: CGFloat
    let start: CFTimeInterval, duration: TimeInterval
    let ease: Ease
    var completion: (@MainActor () -> Void)?

    private init(window: NSWindow, link: CADisplayLink, to: CGFloat, duration: TimeInterval, ease: Ease,
                 completion: (@MainActor () -> Void)?) {
        self.window = window
        self.link = link
        from = window.alphaValue
        self.to = to
        start = CACurrentMediaTime()
        self.duration = duration
        self.ease = ease
        self.completion = completion
    }

    /// From the window's current alpha. A fade already running on it is taken over: it stops
    /// where it is and its completion runs, as a superseded animation's would.
    static func run(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval, ease: Ease,
                    completion: (@MainActor () -> Void)?) {
        stop(window)?()
        guard duration > 0,
              // Before the first orderFront the window has no screen: the main one's link still ticks.
              let screen = window.screen ?? NSScreen.main else {
            window.alphaValue = alpha
            completion?()
            return
        }
        let link = screen.displayLink(target: WindowFade.self, selector: #selector(WindowFade.tick))
        running[ObjectIdentifier(window)] = WindowFade(window: window, link: link, to: alpha, duration: duration,
                                                       ease: ease, completion: completion)
        link.add(to: .main, forMode: .common)
    }

    /// Stops the window's fade where it is; returns its completion for the caller to run (or drop).
    @discardableResult
    static func stop(_ window: NSWindow) -> (@MainActor () -> Void)? {
        guard let fade = running.removeValue(forKey: ObjectIdentifier(window)) else { return nil }
        fade.link.invalidate()
        return fade.completion
    }

    /// The link targets the class, which finds the fade by its link: a link holds its target
    /// strongly, so targeting the fade would keep it alive after its window is gone.
    @objc static func tick(_ link: CADisplayLink) {
        guard let (key, fade) = running.first(where: { $0.value.link === link }) else { return link.invalidate() }
        guard let window = fade.window else {
            running.removeValue(forKey: key)
            return link.invalidate()
        }
        let progress = (link.targetTimestamp - fade.start) / fade.duration
        window.alphaValue = fade.from + (fade.to - fade.from) * fade.ease(progress)
        guard progress >= 1 else { return }
        running.removeValue(forKey: key)
        link.invalidate()
        fade.completion?()
    }
}

/// `matchedGeometryEffect` only when things may move: fades-only mode crossfades instead.
struct GlideModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    let enabled: Bool
    var properties: MatchedGeometryProperties = .frame

    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: id, in: namespace, properties: properties)
        } else {
            content
        }
    }
}

/// A deleted row's exit: its height closes up while it fades, so the rows below slide up into the gap.
struct CollapseModifier: ViewModifier {
    let fraction: Double
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: height * fraction, alignment: .top)
            .clipped()
            .opacity(fraction)
    }
}

extension AnyTransition {
    /// List rows: inserts drop in from above while fading, deletes collapse. Fades-only: opacity.
    @MainActor static func listRow(height: CGFloat, moves: Bool) -> AnyTransition {
        guard moves else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                           removal: .modifier(active: CollapseModifier(fraction: 0, height: height),
                                              identity: CollapseModifier(fraction: 1, height: height)))
    }
}
