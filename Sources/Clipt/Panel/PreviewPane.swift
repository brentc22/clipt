import SwiftUI
import CliptCore

/// The right side: the selected item in a rounded box, then From / Copied / Type.
struct PreviewPane: View {
    let content: PreviewContent?
    let meta: PreviewMeta?
    /// The item shown; a new one crossfades in over the old.
    let itemID: Int64?
    let crossfade: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                box
                if let meta { MetaGrid(meta: meta) }
            }
            .id(itemID)
            .transition(.opacity)
        }
        // Overrides the selection's spring for this pane: a crossfade, or nothing on a held key.
        .animation(crossfade ? Motion.quick : nil, value: itemID)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var box: some View {
        ZStack {
            switch content {
            case .text(let text):
                ScrollView {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .scrollIndicators(.automatic)
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 6))
                    .padding(10)
            case .color(let color, let hex):
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: color))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                    Text(hex.uppercased())
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            case .files(let urls):
                FileList(urls: urls)
            case nil:
                Image(systemName: "list.clipboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct FileList: View {
    let urls: [URL]
    private let shown = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(urls.prefix(shown).enumerated()), id: \.offset) { _, url in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(url.lastPathComponent)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if urls.count > shown {
                Text("and \(urls.count - shown) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MetaGrid: View {
    let meta: PreviewMeta

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            row("From", meta.source)
            row("Copied", PanelFormat.relative(meta.copiedAt))
            row("Type", meta.type)
        }
        .font(.system(size: 11))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).fontWeight(.medium).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
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

/// The From / Copied / Type grid under the preview.
struct PreviewMeta: Equatable {
    let source: String
    let copiedAt: Date
    let type: String
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
                let cg = await Task.detached(priority: .userInitiated) { Thumbnails.downsample(data, maxPixel: 900) }.value
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
        PreviewMeta(source: item.sourceAppName ?? "Unknown app", copiedAt: item.copiedAt,
                    type: PanelFormat.typeLine(kind: item.kind, characters: characters,
                                               byteSize: item.byteSize, fileCount: files))
    }

    private static func image(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
