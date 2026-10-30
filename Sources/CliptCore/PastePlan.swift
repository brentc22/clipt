import Foundation

public enum CopyOnlyReason: Equatable, Sendable { case noAccessibility, noTargetApp }

public enum PasteRoute: Equatable, Sendable {
    case synthesizeCommandV
    case copyOnly(CopyOnlyReason)
}

/// Pure decisions behind pasting, so they can be tested without a pasteboard or a keyboard.
public enum PastePlan {
    public static let finderBundleID = "com.apple.finder"

    /// Pasting needs a running target app other than Clipt, and Accessibility to post ⌘V.
    /// Finder (the desktop) only takes files: ⌘V with text or an image there does nothing,
    /// so those are copied and the toast says so.
    public static func route(hasAccessibility: Bool, targetPID: Int32?, targetIsRunning: Bool, ownPID: Int32,
                             targetBundleID: String?, kind: ClipKind) -> PasteRoute {
        guard let targetPID, targetIsRunning, targetPID != ownPID else { return .copyOnly(.noTargetApp) }
        if targetBundleID == finderBundleID, kind != .file { return .copyOnly(.noTargetApp) }
        return hasAccessibility ? .synthesizeCommandV : .copyOnly(.noAccessibility)
    }

    /// How representations map onto pasteboard items. A Finder copy of several files is one
    /// item per file, each with one `public.file-url`; a single item can hold only one value
    /// per type. The first item keeps every other representation plus the first file URL;
    /// each further file URL gets an item of its own, in order.
    public static func pasteboardItems(_ reps: [Representation]) -> [[Representation]] {
        var first: [Representation] = []
        var more: [[Representation]] = []
        var sawFileURL = false
        for rep in reps {
            if rep.type == PasteType.fileURL {
                if sawFileURL { more.append([rep]); continue }
                sawFileURL = true
            }
            first.append(rep)
        }
        return first.isEmpty ? more : [first] + more
    }

    /// The kind that decides the route: a plain-text paste of a file writes only its text.
    public static func pasteKind(_ kind: ClipKind, writing reps: [Representation]) -> ClipKind {
        guard kind == .file else { return kind }
        return reps.contains { $0.type == PasteType.fileURL } ? .file : .text
    }

    /// Plain-text paste writes only the plain-text representation; an item without one is unchanged.
    public static func representations(_ reps: [Representation], plainText: Bool) -> [Representation] {
        guard plainText else { return reps }
        let text = reps.filter { $0.type == PasteType.plainText }
        return text.isEmpty ? reps : text
    }
}
