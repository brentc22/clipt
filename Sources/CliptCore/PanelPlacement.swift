import CoreGraphics

public enum PanelPlacement {
    public static let size = CGSize(width: 640, height: 404)

    /// `screens` are visible frames in AppKit coordinates (origin bottom-left). Uses the
    /// screen under the mouse (first screen as fallback), centered horizontally, with the
    /// panel's top 22% of the screen height below the top.
    public static func frame(screens: [CGRect], mouse: CGPoint) -> CGRect {
        let screen = screens.first { $0.contains(mouse) } ?? screens.first ?? .zero
        return CGRect(x: screen.midX - size.width / 2,
                      y: screen.maxY - screen.height * 0.22 - size.height,
                      width: size.width, height: size.height)
    }
}
