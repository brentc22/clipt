import SwiftUI
import CliptCore

/// The right side: the selected item in a rounded box, then one line of metadata.
struct PreviewPane: View {
    let content: PreviewContent?
    let meta: PreviewMeta?
    /// The item shown; a new one crossfades in over the old.
    let itemID: Int64?
    let crossfade: Bool

    /// Images are shown small: never taller than this.
    private static let maxImageHeight: CGFloat = 150

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                box
                if let meta {
                    Text(meta.line)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        // The middle goes first, so the source and the size both stay.
                        .truncationMode(.middle)
                        .padding(.horizontal, 2)
                }
            }
            .id(itemID)
            .transition(.opacity)
        }
        // Overrides the selection's spring for this pane: a crossfade, or nothing on a held key.
        .animation(crossfade ? Motion.quick : nil, value: itemID)
        .padding(EdgeInsets(top: 8, leading: 4, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var box: some View {
        ZStack {
            switch content {
            case .text(let text):
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .scrollIndicators(.automatic)
            case .image(let image):
                // At most 150 pt tall and never past the original's size on a Retina screen,
                // so the thumbnail and the sharper image that replaces it lay out the same.
                let cap = meta?.pixelSize.map { CGSize(width: CGFloat($0.width) / 2, height: CGFloat($0.height) / 2) }
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: cap?.width ?? .infinity,
                           maxHeight: min(Self.maxImageHeight, cap?.height ?? .infinity))
                    .clipShape(.rect(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .color(let color, let hex):
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: color))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .frame(width: 64, height: 64)
                    Text(hex.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .files(let urls):
                FileList(urls: urls)
            case nil:
                Image(systemName: "list.clipboard")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 9, style: .continuous))
    }
}

private struct FileList: View {
    let urls: [URL]
    private let shown = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(urls.prefix(shown).enumerated()), id: \.offset) { _, url in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if urls.count > shown {
                Text("and \(urls.count - shown) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Content and loading

/// What the preview pane shows for the selected item.
enum PreviewContent {
    /// At most `PanelFormat.previewCharacterLimit` characters.
    case text(String)
    case image(NSImage)
    case files([URL])
    case color(NSColor, String)
}

/// What the line under the preview says: "Safari · just now · 3024 × 1964 · 2.4 MB".
struct PreviewMeta: Equatable {
    let source: String
    let copiedAt: Date
    let kind: ClipKind
    let characters: Int?
    let byteSize: Int
    let fileCount: Int?
    let pixelSize: PixelSize?

    /// Formatted when drawn, so "just now" ages with the panel.
    var line: String {
        PanelFormat.metaLine(source: source, copiedAt: copiedAt, kind: kind, characters: characters,
                             byteSize: byteSize, fileCount: fileCount, pixelSize: pixelSize)
    }
}

/// Loads the preview for one item at a time; a newer `load` or `cancel` drops older results.
/// Nothing here touches the disk on the main thread: the show path runs through it.
@MainActor
final class PreviewLoader {
    typealias Apply = @MainActor (PreviewContent?, PreviewMeta?) -> Void

    private(set) var itemID: Int64?
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        itemID = nil
    }

    /// Calls `apply` at once with what the row already has, then again as fuller content arrives.
    func load(_ item: ClipItem?, apply: @escaping Apply) {
        cancel()
        guard let item else { return apply(nil, nil) }
        itemID = item.id
        let id = item.id
        var content: PreviewContent?
        var meta = Self.meta(item)
        let isCurrent = { [weak self] in !Task.isCancelled && self?.itemID == id }

        switch item.kind {
        case .text, .link:
            content = .text(item.preview)
            task = Task {
                guard let full = await History.shared.fullText(of: id) else { return }
                // Counting a multi-megabyte string is not main-thread work.
                let (shown, count) = await Task.detached(priority: .userInitiated) {
                    (String(full.prefix(PanelFormat.previewCharacterLimit)), full.count)
                }.value
                guard isCurrent() else { return }
                content = .text(shown)
                meta = Self.meta(item, characters: count)
                apply(content, meta)
            }
        case .color:
            let hex = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if let c = PanelFormat.hexColor(hex) {
                content = .color(NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha), hex)
            } else {
                content = .text(hex)
            }
        case .image:
            let thumbURL = item.thumbnailURL
            task = Task {
                // The stored thumbnail first, decoded off main.
                if let thumbURL {
                    let cg = await Task.detached(priority: .userInitiated) { Thumbnails.downsample(thumbURL, maxPixel: 256) }.value
                    guard isCurrent() else { return }
                    if let cg { content = .image(Self.image(cg)); apply(content, meta) }
                }
                // The full image only once the selection rests: holding ↓ over images must not queue big reads.
                try? await Task.sleep(for: .milliseconds(120))
                guard isCurrent() else { return }
                let reps = await History.shared.representations(of: id)
                guard isCurrent(),
                      let data = (reps.first { $0.type == PasteType.png } ?? reps.first { $0.type == PasteType.tiff })?.data
                else { return }
                // 480 px covers the box (about 205 × 150 pt) at 2x; images are previewed small.
                let cg = await Task.detached(priority: .userInitiated) { Thumbnails.downsample(data, maxPixel: 480) }.value
                guard isCurrent(), let cg else { return }
                content = .image(Self.image(cg))
                apply(content, meta)
            }
        case .file:
            content = .files([])
            task = Task {
                let reps = await History.shared.representations(of: id)
                let urls = reps.filter { $0.type == PasteType.fileURL }
                    .compactMap { String(data: $0.data, encoding: .utf8).flatMap(URL.init(string:)) }
                guard isCurrent() else { return }
                content = .files(urls)
                meta = Self.meta(item, files: urls.count)
                apply(content, meta)
            }
        }
        apply(content, meta)
    }

    private static func meta(_ item: ClipItem, characters: Int? = nil, files: Int? = nil) -> PreviewMeta {
        PreviewMeta(source: item.sourceAppName ?? "Unknown app", copiedAt: item.copiedAt, kind: item.kind,
                    characters: characters, byteSize: item.byteSize, fileCount: files, pixelSize: item.pixelSize)
    }

    private static func image(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
