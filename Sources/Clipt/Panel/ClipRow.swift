import SwiftUI
import CliptCore

/// One list row. Takes plain values and is Equatable, so moving the selection only
/// re-renders the two rows whose `selected` changed.
struct ClipRow: View, Equatable {
    let item: ClipItem
    let selected: Bool
    let hotkey: Int?

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: AppIcons.icon(for: item.sourceBundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background {
            // The one highlight; Task 8 gives it a matchedGeometryEffect so it glides.
            if selected { SelectionHighlight() }
        }
        .contentShape(.rect)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            HStack(spacing: 8) {
                if let url = item.thumbnailURL { RowThumbnail(url: url) }
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
        case .color:
            HStack(spacing: 6) {
                if let c = PanelFormat.hexColor(item.preview) {
                    Circle()
                        .fill(Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha))
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .frame(width: 11, height: 11)
                }
                previewText
            }
        default:
            previewText
        }
    }

    private var previewText: some View {
        Text(item.preview)
            .font(.system(size: 13))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private var trailing: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .rotationEffect(.degrees(45))
                .opacity(selected ? 0.85 : 0.4)
        } else if let hotkey {
            Text("⌘\(hotkey)")
                .font(.system(size: 11).monospacedDigit())
                .opacity(selected ? 0.85 : 0.45)
        }
    }
}

/// A 20 pt-tall thumbnail whose width follows the image (capped), loaded off main.
private struct RowThumbnail: View {
    let url: URL
    // `State` as a plain property: the `@State` macro's plugin is missing from the Command Line Tools toolchain.
    private let loaded: State<NSImage?>
    private var image: NSImage? { loaded.wrappedValue }
    private static let maxPixel = 112   // 56 pt wide at 2x

    init(url: URL) {
        self.url = url
        loaded = State(initialValue: Thumbnails.cached(url, maxPixel: Self.maxPixel))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: min(56, 20 * image.size.width / max(image.size.height, 1)), height: 20)
            } else {
                Color.primary.opacity(0.06).frame(width: 30, height: 20)
            }
        }
        .clipShape(.rect(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        .task(id: url) {
            if image == nil { loaded.wrappedValue = await Thumbnails.load(url, maxPixel: Self.maxPixel) }
        }
    }
}

/// The accent-colored rounded rect behind the selected row.
struct SelectionHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.accentColor)
    }
}

/// "PINNED" / "RECENT".
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
