import Foundation

/// What the panel shows: pinned rows on top, then recent rows. Pure value, so the
/// selection and ⌘1…9 rules are testable without a window.
public struct PanelList: Equatable, Sendable {
    public private(set) var pinned: [ClipItem]
    public private(set) var recent: [ClipItem]
    public private(set) var selection: Int64?
    /// True once the store has no more pages. `init` and `replace` derive it from
    /// `recent.count < pageSize` (a short first page means nothing more to fetch);
    /// `appendPage` sets it when it receives fewer than `pageSize` rows.
    public private(set) var isExhausted: Bool

    public static let pageSize = 50

    public var rows: [ClipItem] { pinned + recent }

    /// Opens on the newest recent item, else the first pin.
    public init(pinned: [ClipItem], recent: [ClipItem]) {
        self.pinned = pinned
        self.recent = recent
        self.selection = (recent.first ?? pinned.first)?.id
        self.isExhausted = recent.count < Self.pageSize
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

    /// Rows already shown are dropped: an item copied while paging by offset shifts
    /// rows and would otherwise repeat one, breaking id-based selection and ⌘N.
    public mutating func appendPage(_ more: [ClipItem]) {
        var seen = Set(rows.map(\.id))
        recent += more.filter { seen.insert($0.id).inserted }
        if more.count < Self.pageSize { isExhausted = true }
    }

    /// Drops a row in place (a delete, before the store confirms it). A removed selection
    /// moves to the row that took its place, else the one above; paging state is kept.
    public mutating func remove(_ id: Int64) {
        let rows = rows
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        pinned.removeAll { $0.id == id }
        recent.removeAll { $0.id == id }
        guard selection == id else { return }
        let after = self.rows
        selection = after.isEmpty ? nil : after[min(index, after.count - 1)].id
    }

    /// No further pages, e.g. for search results, which arrive in one piece.
    public mutating func markExhausted() { isExhausted = true }

    /// 1…9 is the position among the visible recent rows; pins never get a number.
    public func hotkeyNumber(for id: Int64) -> Int? {
        guard let i = recent.prefix(9).firstIndex(where: { $0.id == id }) else { return nil }
        return i + 1
    }

    public func item(forHotkey n: Int) -> ClipItem? {
        guard (1...9).contains(n), n <= recent.count else { return nil }
        return recent[n - 1]
    }

    /// The selection is within 10 rows of the end of `recent` and more pages may exist.
    public var needsNextPage: Bool {
        guard !isExhausted else { return false }
        let index = recent.firstIndex { $0.id == selection } ?? -1
        return index >= recent.count - 10
    }
}

/// What the panel may do in response to a list change. While hidden (a revision reload
/// after a copy), the list stays fresh for the next open, but nothing decodes an image,
/// reads full text or pages in more rows.
public enum PanelWork {
    public static func loadsPreview(visible: Bool, selection: Int64?, loadedID: Int64?) -> Bool {
        visible && selection != loadedID
    }

    public static func pagesIn(visible: Bool, needsNextPage: Bool) -> Bool {
        visible && needsNextPage
    }
}
