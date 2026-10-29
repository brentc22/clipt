import Foundation

/// What the panel shows: pinned rows on top, then recent rows. Pure value, so the
/// selection and ⌘1…9 rules are testable without a window.
public struct PanelList: Equatable, Sendable {
    public private(set) var pinned: [ClipItem]
    public private(set) var recent: [ClipItem]
    public private(set) var selection: Int64?

    public var rows: [ClipItem] { pinned + recent }

    /// Opens on the newest recent item, else the first pin.
    public init(pinned: [ClipItem], recent: [ClipItem]) {
        self.pinned = pinned
        self.recent = recent
        self.selection = (recent.first ?? pinned.first)?.id
    }

    /// Clamped at both ends, no wrap.
    public mutating func moveSelection(by delta: Int) {
        let rows = rows
        guard !rows.isEmpty else { selection = nil; return }
        let current = rows.firstIndex { $0.id == selection } ?? 0
        selection = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    public mutating func select(_ id: Int64) {
        guard rows.contains(where: { $0.id == id }) else { return }
        selection = id
    }

    /// Keeps the selection when it is still present, unless `resetSelection`.
    public mutating func replace(pinned: [ClipItem], recent: [ClipItem], resetSelection: Bool) {
        let previous = selection
        self = PanelList(pinned: pinned, recent: recent)
        if !resetSelection, let previous, rows.contains(where: { $0.id == previous }) {
            selection = previous
        }
    }

    public mutating func appendPage(_ more: [ClipItem]) {
        recent += more
    }

    /// 1…9 is the position among the visible recent rows; pins never get a number.
    public func hotkeyNumber(for id: Int64) -> Int? {
        guard let i = recent.prefix(9).firstIndex(where: { $0.id == id }) else { return nil }
        return i + 1
    }

    public func item(forHotkey n: Int) -> ClipItem? {
        guard (1...9).contains(n), n <= recent.count else { return nil }
        return recent[n - 1]
    }

    /// The selection is within 10 rows of the end of `recent`.
    public var needsNextPage: Bool {
        let index = recent.firstIndex { $0.id == selection } ?? -1
        return index >= recent.count - 10
    }
}
