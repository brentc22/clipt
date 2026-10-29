import CoreGraphics
@preconcurrency import Vision

/// On-device text recognition (Apple Vision) — nothing leaves the Mac.
/// Adapted from Glint's TextRecognizer: only `text(in:)` and what it needs.
public enum TextRecognizer {
    struct Line: Sendable {
        let text: String
        /// Image pixels, top-left origin.
        let frame: CGRect
    }

    /// All text in the image, top to bottom. Vision often returns one line in pieces
    /// (a label, then a value); pieces at the same height are joined left to right.
    public static func text(in image: CGImage) async -> String {
        joinRows(await recognize(image))
    }

    static func joinRows(_ lines: [Line]) -> String {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let last = rows.last?.first,
               abs(last.frame.midY - line.frame.midY) < min(last.frame.height, line.frame.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static func recognize(_ image: CGImage) async -> [Line] {
        // Background indexing: stay out of the way of the foreground app.
        await Task.detached(priority: .utility) {
            // Vision scales the whole image to its working size, so on a tall scrolling
            // capture the text ends up too small to read. Tall images go in overlapping
            // tiles; a line found twice in an overlap is kept once.
            var found: [Line] = []
            for tile in tiles(width: image.width, height: image.height) {
                guard let piece = image.cropping(to: tile) else { continue }
                for line in recognizeTile(piece) {
                    let frame = line.frame.offsetBy(dx: 0, dy: tile.minY)
                    let duplicate = found.contains { $0.text == line.text && $0.frame.intersects(frame) }
                    if !duplicate { found.append(Line(text: line.text, frame: frame)) }
                }
            }
            return found.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        }.value
    }

    /// Tiles at most 1.5× as tall as wide (min 1000 px), overlapping by 80 px so no line
    /// is only ever seen cut in half.
    static func tiles(width: Int, height: Int) -> [CGRect] {
        let tileHeight = max(1000, width * 3 / 2)
        guard height > tileHeight else { return [CGRect(x: 0, y: 0, width: width, height: height)] }
        let overlap = 80
        return stride(from: 0, to: height - overlap, by: tileHeight - overlap).map {
            CGRect(x: 0, y: $0, width: width, height: min(tileHeight, height - $0))
        }
    }

    private static func recognizeTile(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction "fixes" codes, keys and IBANs into dictionary words.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).compactMap { observation -> Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Line(text: candidate.string, frame: pixels(observation.boundingBox, size))
        }
    }

    /// Vision's normalized, bottom-left boxes → image pixels, top-left origin.
    static func pixels(_ box: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
               width: box.width * size.width, height: box.height * size.height)
    }
}
