import CryptoKit
import Foundation

public enum ClipClassifier {
    public static let sizeCap = 20_000_000
    static let previewLimit = 300

    public static func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        var reps = snapshot.representations
        let total = reps.reduce(0) { $0 + $1.data.count }
        if total > sizeCap { reps = reps.filter { PasteType.understood.contains($0.type) } }

        let text = reps.first { $0.type == PasteType.plainText }
            .flatMap { String(data: $0.data, encoding: .utf8) }
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let image = reps.first { $0.type == PasteType.png } ?? reps.first { $0.type == PasteType.tiff }
        let fileReps = reps.filter { $0.type == PasteType.fileURL }
        let fileURLs = fileReps.compactMap { String(data: $0.data, encoding: .utf8) }
            .filter { !$0.isEmpty }

        let kind: ClipKind
        let primary: Data
        let preview: String
        if !fileURLs.isEmpty {
            kind = .file
        } else if image != nil {
            kind = .image
        } else if let text {
            kind = classifyText(text)
        } else {
            return nil
        }

        // Primary representation: plain text, then image, then file URLs.
        if let text {
            primary = Data(text.utf8)
        } else if let image {
            primary = image.data
        } else {
            primary = Data(fileURLs.joined(separator: "\n").utf8)
        }

        if let text {
            preview = collapse(text)
        } else if kind == .file {
            preview = collapse(fileURLs.joined(separator: " "))
        } else {
            preview = "Image"
        }

        let hash = SHA256.hash(data: primary).map { String(format: "%02x", $0) }.joined()
        return ClipContent(kind: kind, plainText: text, preview: preview, primaryHash: hash, representations: reps)
    }

    private static func classifyText(_ text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSingleWebURL(trimmed) { return .link }
        if trimmed.range(of: "^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$", options: .regularExpression) != nil {
            return .color
        }
        return .text
    }

    private static func isSingleWebURL(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace),
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    private static func collapse(_ s: String) -> String {
        // Only scan as much as can matter: 300 collapsed chars need at most a bounded prefix of non-space chars.
        var out = ""
        var pendingSpace = false
        for ch in s {
            if ch.isWhitespace {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace { out.append(" "); pendingSpace = false }
            out.append(ch)
            if out.count >= previewLimit { break }
        }
        return out
    }
}
