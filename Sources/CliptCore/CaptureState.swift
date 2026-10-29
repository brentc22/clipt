import Foundation

public enum CaptureState: Equatable, Sendable {
    case active, pausedByUser, noPasteboardAccess
}

public enum CaptureGate {
    /// The user's own pause wins: it is the one the user can act on from the menu.
    public static func state(userPaused: Bool, accessAllowed: Bool) -> CaptureState {
        if userPaused { return .pausedByUser }
        return accessAllowed ? .active : .noPasteboardAccess
    }
}

/// Remembers pasteboard changes Clipt made itself (pasting a history item), so the
/// monitor bumps that item instead of capturing the write as a new copy.
public struct OwnWriteTracker: Sendable {
    private var pending: [Int: Int64] = [:]
    public init() {}

    public mutating func recordWrite(changeCount: Int, itemID: Int64) {
        pending[changeCount] = itemID
        // Writes the monitor never saw (it was paused) must not pile up.
        if pending.count > 16, let oldest = pending.keys.min() { pending[oldest] = nil }
    }

    /// Returns the item id once if this change was ours.
    public mutating func claim(changeCount: Int) -> Int64? {
        pending.removeValue(forKey: changeCount)
    }
}
