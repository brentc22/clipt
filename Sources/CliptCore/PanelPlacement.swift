import CoreGraphics

public enum PanelPlacement {
    public static let size = CGSize(width: 540, height: 330)

    public struct Screen: Sendable, Equatable {
        /// The whole display, menu bar and Dock included: what the mouse is tested against.
        public let frame: CGRect
        /// The part outside the menu bar and Dock: where the panel goes.
        public let visible: CGRect
        public init(frame: CGRect, visible: CGRect) {
            self.frame = frame
            self.visible = visible
        }
    }

    /// AppKit coordinates (origin bottom-left). Uses the screen under the mouse, even when
    /// the mouse is in its menu bar or Dock (first screen as fallback); the panel is
    /// centered horizontally in that screen's visible frame, with its top 22% of the
    /// visible height below the visible top.
    public static func frame(screens: [Screen], mouse: CGPoint) -> CGRect {
        let screen = (screens.first { $0.frame.contains(mouse) } ?? screens.first)?.visible ?? .zero
        return CGRect(x: screen.midX - size.width / 2,
                      y: screen.maxY - screen.height * 0.22 - size.height,
                      width: size.width, height: size.height)
    }
}
