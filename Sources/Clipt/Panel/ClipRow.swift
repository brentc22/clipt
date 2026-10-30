import SwiftUI
import CliptCore

/// One list row. Takes plain values and is Equatable, so moving the selection only
/// re-renders the two rows whose `selected` changed.
struct ClipRow: View, Equatable {
    let item: ClipItem
    let selected: Bool
    let hotkey: Int?

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AppIcons.icon(for: item.sourceBundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: PanelView.rowHeight)
        .foregroundStyle(selected ? Color.white : Color.primary)
        // The highlight is drawn by the list (PanelView.rows), one view handed between rows.
        .contentShape(.rect)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            HStack(spacing: 7) {
                if let url = item.thumbnailURL { RowThumbnail(url: url) }
                // "3024 × 1964" rather than the stored "Image".
                Text(PanelFormat.rowText(kind: item.kind, preview: item.preview, pixelSize: item.pixelSize))
                    .font(.system(size: 12).monospacedDigit())
                    .lineLimit(1)
            }
        case .color:
            HStack(spacing: 7) {
                if let c = PanelFormat.hexColor(item.preview) {
                    Circle()
                        .fill(Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha))
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .frame(width: 9, height: 9)
                }
                previewText
            }
        default:
            previewText
        }
    }

    private var previewText: some View {
        Text(item.preview)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private var trailing: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .rotationEffect(.degrees(45))
                .opacity(selected ? 0.85 : 0.4)
        } else if let hotkey {
            Text("⌘\(hotkey)")
                .font(.system(size: 10.5).monospacedDigit())
                .opacity(selected ? 0.85 : 0.45)
        }
    }
}

/// A 26 × 17 pt thumbnail, cropped to fill, loaded off main.
private struct RowThumbnail: View {
    let url: URL
    // `State` as a plain property: the `@State` macro's plugin is missing from the Command Line Tools toolchain.
    private let loaded: State<NSImage?>
    private var image: NSImage? { loaded.wrappedValue }
    private static let size = CGSize(width: 26, height: 17)
    /// Longest side in pixels: enough to fill 26 × 17 pt at 2x for all but very tall images.
    private static let maxPixel = 112

    init(url: URL) {
        self.url = url
        loaded = State(initialValue: Thumbnails.cached(url, maxPixel: Self.maxPixel))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .task(id: url) {
            if image == nil { loaded.wrappedValue = await Thumbnails.load(url, maxPixel: Self.maxPixel) }
        }
    }
}

/// The accent-colored rounded rect behind the selected row; the list glides it between rows.
struct SelectionHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.accentColor)
    }
}

/// "PINNED" / "RECENT".
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
