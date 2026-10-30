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

/// Mirrors `NSPasteboard.AccessBehavior` (Core stays free of AppKit).
public enum PasteboardBehavior: Sendable, CaseIterable {
    /// Not decided yet: macOS asks the user the first time an app reads the pasteboard
    /// programmatically. An app shows up in "Paste from Other Apps" only after that alert.
    case notDecided
    case ask, alwaysAllow, alwaysDeny
    /// A value newer than this code.
    case unknown
}

/// What Settings and onboarding show for the "Paste from Other Apps" permission.
public enum PasteboardAccessStatus: Equatable, Sendable {
    case allowed, notDecided, denied
}

public enum PasteboardAccess {
    /// Capture runs on `.alwaysAllow` and on `.notDecided`: the first read raises macOS's
    /// one-time alert, and the user's answer decides from then on. `.ask` (an alert on every
    /// copy) and `.alwaysDeny` pause capture.
    public static func capturesAllowed(_ behavior: PasteboardBehavior) -> Bool {
        switch behavior {
        case .alwaysAllow, .notDecided: true
        case .ask, .alwaysDeny, .unknown: false
        }
    }

    /// Green only for an explicit Allow; "not decided" is its own state, not a success.
    public static func status(_ behavior: PasteboardBehavior) -> PasteboardAccessStatus {
        switch behavior {
        case .alwaysAllow: .allowed
        case .notDecided: .notDecided
        case .ask, .alwaysDeny, .unknown: .denied
        }
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
