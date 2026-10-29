import SwiftUI
import CliptCore

/// The right side: the selected item in a rounded box, then From / Copied / Type.
struct PreviewPane: View {
    let content: PreviewContent?
    let meta: PreviewMeta?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            box
            if let meta { MetaGrid(meta: meta) }
        }
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
