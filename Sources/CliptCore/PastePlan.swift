import Foundation

public enum CopyOnlyReason: Equatable, Sendable { case noAccessibility, noTargetApp }

public enum PasteRoute: Equatable, Sendable {
    case synthesizeCommandV
    case copyOnly(CopyOnlyReason)
}

/// Pure decisions behind pasting, so they can be tested without a pasteboard or a keyboard.
public enum PastePlan {
    /// Pasting needs a running target app other than Clipt, and Accessibility to post ⌘V.
    public static func route(hasAccessibility: Bool, targetPID: Int32?, targetIsRunning: Bool, ownPID: Int32) -> PasteRoute {
        guard let targetPID, targetIsRunning, targetPID != ownPID else { return .copyOnly(.noTargetApp) }
        return hasAccessibility ? .synthesizeCommandV : .copyOnly(.noAccessibility)
    }

    /// Plain-text paste writes only the plain-text representation; an item without one is unchanged.
    public static func representations(_ reps: [Representation], plainText: Bool) -> [Representation] {
        guard plainText else { return reps }
        let text = reps.filter { $0.type == PasteType.plainText }
        return text.isEmpty ? reps : text
    }
}
