import Foundation

/// The words and numbers the panel shows. Pure, so the copy is testable.
public enum PanelFormat {
    /// The preview pane shows at most this many characters of a text.
    public static let previewCharacterLimit = 20_000

    /// "just now", "2 min ago", "3 hr ago", "yesterday", "4 days ago", then a short date.
    public static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? hours / 24
        if days <= 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return sameYear ? date.formatted(.dateTime.day().month(.abbreviated)) : date.formatted(style)
    }

    /// The "Type" line: "Link · 36 characters", "Image · 1.2 MB", "Files · 3 items".
    /// `characters` is nil while the full text is still loading.
    public static func typeLine(kind: ClipKind, characters: Int?, byteSize: Int, fileCount: Int? = nil,
                                locale: Locale = .current) -> String {
        switch kind {
        case .text, .link:
            let name = kind == .link ? "Link" : "Text"
            guard let characters else { return name }
            return "\(name) · \(count(characters, "character", locale))"
        case .color:
            return "Color"
        case .image:
            return "Image · " + ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
        case .file:
            guard let fileCount, fileCount != 1 else { return "File" }
            return "Files · \(count(fileCount, "item", locale))"
        }
    }

    /// "1 character", "1,204 characters".
    static func count(_ n: Int, _ noun: String, _ locale: Locale) -> String {
        "\(n.formatted(.number.grouping(.automatic).locale(locale))) \(noun)\(n == 1 ? "" : "s")"
    }

    /// `#RRGGBB` or `#RRGGBBAA`, hash optional, as components in 0…1.
    public static func hexColor(_ s: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var hex = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let full = hex.count == 6 ? (value << 8) | 0xFF : value
        func byte(_ shift: UInt64) -> Double { Double((full >> shift) & 0xFF) / 255 }
        return (byte(24), byte(16), byte(8), byte(0))
    }
}

/// A key the panel reacts to, independent of SwiftUI's event types.
public enum PanelKey: Equatable, Sendable {
    case up, down, enter, backspace, escape
    case character(Character)
}

/// What a key press does in the panel.
public enum PanelCommand: Equatable, Sendable {
    case move(Int)
    case paste(plainText: Bool)
    case pasteHotkey(Int)
    case togglePin
    case delete
    case escape

    /// Nil means the key is not the panel's: the search field gets it (typing, ⌫ while searching).
    public static func resolve(_ key: PanelKey, command: Bool, option: Bool, queryIsEmpty: Bool) -> PanelCommand? {
        switch key {
        case .up: return .move(-1)
        case .down: return .move(1)
        case .enter: return .paste(plainText: option)
        case .escape: return .escape
        case .backspace: return queryIsEmpty && !command && !option ? .delete : nil
        case .character(let c):
            guard command else { return nil }
            if let n = c.wholeNumberValue, (1...9).contains(n) { return .pasteHotkey(n) }
            if c == "p" || c == "P" { return .togglePin }
            return nil
        }
    }
}
