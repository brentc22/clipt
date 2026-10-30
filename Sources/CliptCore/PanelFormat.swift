import Foundation

/// The words and numbers the panel shows. Pure, so the copy is testable.
public enum PanelFormat {
    /// The preview pane shows at most this many characters of a text.
    public static let previewCharacterLimit = 20_000
    /// All UI text is English, so dates, sizes and numbers are too, whatever the system locale.
    public static let locale = Locale(identifier: "en_US")

    /// "just now", "2 min ago", "3 hr ago", "yesterday", "4 days ago", then a short date.
    public static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
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
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return sameYear ? date.formatted(base.day().month(.abbreviated))
                        : date.formatted(base.day().month(.abbreviated).year())
    }

    /// "3024 × 1964": an image's pixel size, as an image row and the meta line show it.
    public static func dimensions(_ size: PixelSize) -> String {
        "\(size.width) \u{00D7} \(size.height)"
    }

    /// What a list row says: an image's pixel size when known, else the stored preview.
    public static func rowText(kind: ClipKind, preview: String, pixelSize: PixelSize?) -> String {
        if kind == .image, let pixelSize { return dimensions(pixelSize) }
        return preview
    }

    /// The one line under the preview: where from, when, and what it is.
    /// "Safari · just now · 3024 × 1964 · 2.4 MB", "Mail · 2 min ago · 1,204 characters",
    /// "Finder · yesterday · 3 items". `characters` and `fileCount` are nil while loading.
    public static func metaLine(source: String, copiedAt: Date, kind: ClipKind, characters: Int?, byteSize: Int,
                                fileCount: Int? = nil, pixelSize: PixelSize? = nil, now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        var parts = [source, relative(copiedAt, now: now, calendar: calendar)]
        switch kind {
        case .text, .link:
            if let characters { parts.append(count(characters, "character")) }
        case .color:
            break
        case .image:
            if let pixelSize { parts.append(dimensions(pixelSize)) }
            parts.append(Int64(byteSize).formatted(.byteCount(style: .file).locale(locale)))
        case .file:
            if let fileCount { parts.append(count(fileCount, "item")) }
        }
        return parts.joined(separator: " · ")
    }

    /// "1 character", "1,204 characters".
    static func count(_ n: Int, _ noun: String) -> String {
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

    /// Physical number-row keys (kVK_ANSI_1…9), so ⌘1–⌘9 work on AZERTY, where the
    /// unshifted keys type & é " ' ( § è ! ç.
    public static func hotkeyNumber(keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: 1
        case 19: 2
        case 20: 3
        case 21: 4
        case 23: 5
        case 22: 6
        case 26: 7
        case 28: 8
        case 25: 9
        default: nil
        }
    }

    /// Nil means the key is not the panel's: the search field gets it (typing, ⌫ while searching).
    /// `keyCode` is the physical key when known. Auto-repeat only moves the selection: a held
    /// ⌫ must stop at an empty field instead of deleting history, and a held ↩ or ⌘N must not
    /// paste twice.
    public static func resolve(_ key: PanelKey, command: Bool, option: Bool, queryIsEmpty: Bool,
                               keyCode: UInt16? = nil, isRepeat: Bool = false) -> PanelCommand? {
        if isRepeat {
            switch key {
            case .up: return .move(-1)
            case .down: return .move(1)
            default: return nil
            }
        }
        switch key {
        case .up: return .move(-1)
        case .down: return .move(1)
        case .enter: return .paste(plainText: option)
        case .escape: return .escape
        case .backspace: return queryIsEmpty && !command && !option ? .delete : nil
        case .character(let c):
            guard command else { return nil }
            if let keyCode {
                if let n = hotkeyNumber(keyCode: keyCode) { return .pasteHotkey(n) }
            } else if let n = c.wholeNumberValue, (1...9).contains(n) {
                return .pasteHotkey(n)
            }
            if c == "p" || c == "P" { return .togglePin }
            return nil
        }
    }
}
