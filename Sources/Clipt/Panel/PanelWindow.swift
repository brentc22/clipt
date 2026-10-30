import AppKit
import CliptCore

/// Borderless, non-activating: it takes keyboard focus without making Clipt the active
/// app, so the app underneath keeps its selection and focus.
final class PanelWindow: NSPanel {
    /// Called for Esc.
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: PanelPlacement.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the glass draws its own shadow
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// The hotkey panel keeps working while an alert (update, clear history) is up.
    override var worksWhenModal: Bool {
        get { true }
        set {}
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
