import Foundation

/// How the app moves, decided from the two switches that can turn movement off. Pure, so
/// the Reduce Motion rules are testable without a window; `Motion` in the app reads it.
public enum MotionStyle: Equatable, Sendable {
    /// Real springs: things scale, slide and glide.
    case springs
    /// Reduce Motion is on, or motion is off in Settings: plain fades, nothing scales or slides.
    case fades

    public init(reduceMotion: Bool, motionEnabled: Bool) {
        self = reduceMotion || !motionEnabled ? .fades : .springs
    }

    /// Every fade in fades-only mode takes this long.
    public static let fadeDuration = 0.12

    /// False means no scale, no slide, no matched-geometry glide.
    public var moves: Bool { self == .springs }

    /// The panel's content grows from this scale as it opens; 1 is no scale.
    public var openScale: Double { moves ? 0.96 : 1 }
    /// And shrinks to this one as it closes.
    public var closeScale: Double { moves ? 0.98 : 1 }
    /// Opening alpha 0 → 1.
    public var openFadeDuration: Double { moves ? 0.18 : Self.fadeDuration }
    /// Closing alpha 1 → 0; the leave spring is cut here, since what is left of it is invisible.
    public var closeDuration: Double { moves ? 0.16 : Self.fadeDuration }
    /// The selected row pulses on paste only when things may scale.
    public var pulsesOnPaste: Bool { moves }
}

/// Timing rules for the panel that keep motion from ever making it slower.
public enum PanelMotion {
    /// List changes stay instant this long after show, so the panel never visibly builds up.
    public static let settleAfterShow = 0.3

    /// The panel is on screen, has its first load in and has finished opening.
    public static func isSettledOpen(visible: Bool, initialLoadLanded: Bool, secondsSinceShow: Double) -> Bool {
        visible && initialLoadLanded && secondsSinceShow >= settleAfterShow
    }

    /// Inserts, deletes and pin moves animate only on a settled panel, and never in fades-only
    /// mode: animating a list change slides the rows around it, which is movement, not a fade.
    public static func animatesListChanges(style: MotionStyle, visible: Bool, initialLoadLanded: Bool,
                                           secondsSinceShow: Double) -> Bool {
        style.moves && isSettledOpen(visible: visible, initialLoadLanded: initialLoadLanded,
                                     secondsSinceShow: secondsSinceShow)
    }

    /// No paste (↩, ⌥↩, ⌘1–9, click) once the panel is on its way out — its paste target is
    /// already gone — or while another paste is under way. Checked before the pasteboard is touched.
    public static func allowsPaste(isClosing: Bool, isPasting: Bool) -> Bool {
        !isClosing && !isPasting
    }

    /// ↩ to ⌘V: the row eases up to `pulseScale` over `pulseLead` and springs back while the
    /// panel closes over `pasteCloseDuration`;
    /// the paste starts once the panel is off screen, or `pasteCloseDuration` after the close
    /// began, whichever comes first.
    public static let pulseLead = 0.05
    public static let pulseScale = 1.02
    public static let pasteCloseDuration = 0.11

    /// Worst case from ↩ until `Paster.paste` starts.
    public static func pasteStartDelay(style: MotionStyle) -> Double {
        (style.pulsesOnPaste ? pulseLead : 0) + pasteCloseDuration
    }

    /// A held arrow key scrolls without animation: a scroll spring would queue up behind the repeat.
    public static func animatesScroll(isKeyRepeat: Bool, style: MotionStyle) -> Bool {
        !isKeyRepeat && style.moves
    }
}

/// A CSS-style cubic-bézier easing curve, (0,0) to (1,1) through two control points. Pure, so
/// the window fades that step it themselves (one display frame at a time) are testable.
public struct Ease: Equatable, Sendable {
    public let x1, y1, x2, y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
    }

    /// Fast start, long soft landing: reads as a spring without overshooting.
    public static let settle = Ease(0.2, 0.9, 0.25, 1)
    /// Leaving: picks up speed, so the eye isn't asked to follow it out.
    public static let exit = Ease(0.4, 0, 1, 1)

    /// The eased value at `progress` (time, 0…1, clamped).
    public func callAsFunction(_ progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        if x == 0 || x == 1 { return x }
        // Solve bezierX(t) = x by bisection: x(t) is monotonic for control x in 0…1.
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            t = (lo + hi) / 2
            if Self.bezier(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return Self.bezier(t, y1, y2)
    }

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
}
