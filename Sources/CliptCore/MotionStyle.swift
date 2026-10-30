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

    /// Inserts, deletes and pin moves animate only on a panel that is on screen, has its first
    /// load in and has finished opening.
    public static func animatesListChanges(visible: Bool, initialLoadLanded: Bool, secondsSinceShow: Double) -> Bool {
        visible && initialLoadLanded && secondsSinceShow >= settleAfterShow
    }

    /// ↩ to ⌘V: the row pulses for `pulseLead`, then the panel closes over `pasteCloseDuration`;
    /// the paste starts once the panel is off screen, or `pasteHandoff` after the close began,
    /// whichever comes first.
    public static let pulseLead = 0.05
    public static let pasteCloseDuration = 0.11
    public static let pasteHandoff = 0.12

    /// Worst case from ↩ until `Paster.paste` starts.
    public static func pasteStartDelay(style: MotionStyle) -> Double {
        (style.pulsesOnPaste ? pulseLead : 0) + min(pasteCloseDuration, pasteHandoff)
    }

    /// A held arrow key scrolls without animation: a scroll spring would queue up behind the repeat.
    public static func animatesScroll(isKeyRepeat: Bool, style: MotionStyle) -> Bool {
        !isKeyRepeat && style.moves
    }
}
