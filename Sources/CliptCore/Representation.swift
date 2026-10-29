import Foundation

/// UTI strings of the pasteboard types Clipt understands.
public enum PasteType {
    public static let plainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let html = "public.html"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let fileURL = "public.file-url"
    public static let url = "public.url"
    public static let understood: Set<String> = [plainText, rtf, html, png, tiff, fileURL, url]
}

public struct Representation: Sendable, Equatable {
    public let type: String
    public let data: Data
    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct PasteboardSnapshot: Sendable {
    /// In pasteboard order.
    public var representations: [Representation]
    public init(representations: [Representation]) {
        self.representations = representations
    }
}

public enum ClipKind: String, Sendable, CaseIterable {
    case text, link, color, image, file
}

public struct ClipContent: Sendable, Equatable {
    public let kind: ClipKind
    /// Full text; nil for pure images.
    public let plainText: String?
    /// Single line, at most 300 characters, whitespace collapsed.
    public let preview: String
    /// Hex SHA-256 of the primary representation.
    public let primaryHash: String
    public let representations: [Representation]

    public var byteSize: Int { representations.reduce(0) { $0 + $1.data.count } }

    public init(kind: ClipKind, plainText: String?, preview: String, primaryHash: String,
                representations: [Representation]) {
        self.kind = kind
        self.plainText = plainText
        self.preview = preview
        self.primaryHash = primaryHash
        self.representations = representations
    }
}
