import SwiftUI
import CliptCore

/// The whole panel: search row, list | preview, footer, on one sheet of Liquid Glass.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool

    private static let topID = "panel-top"

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                SearchRow(query: $model.query, filter: $model.filter, focused: $searchFocused)
                Divider().opacity(0.6)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if model.captureState != .active { banner }
                        list
                    }
                    .frame(width: PanelPlacement.size.width * 0.52)
                    Divider().opacity(0.5)
                    PreviewPane(content: model.preview, meta: model.meta)
                }
                .frame(maxHeight: .infinity)
                Divider().opacity(0.6)
                FooterBar()
            }
            .frame(width: PanelPlacement.size.width, height: PanelPlacement.size.height)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .onKeyPress(phases: .down, action: handle)
        .onChange(of: model.focusRequest, initial: true) { searchFocused = true }
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 6).id(Self.topID)
                    let showHeaders = !model.list.pinned.isEmpty
                    if showHeaders { SectionHeader(title: "Pinned") }
                    rows(model.list.pinned)
                    if showHeaders { SectionHeader(title: "Recent") }
                    rows(model.list.recent)
                    Color.clear.frame(height: 6)
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.automatic)
            .overlay { if model.hasLoaded && model.list.rows.isEmpty { emptyState } }
            .onChange(of: model.list.selection) { _, id in
                guard let id else { return }
                // The first row brings its section header along.
                if id == model.list.rows.first?.id { proxy.scrollTo(Self.topID, anchor: .top) }
                else { proxy.scrollTo(id) }
            }
        }
    }

    private func rows(_ items: [ClipItem]) -> some View {
        ForEach(items) { item in
            ClipRow(item: item, selected: item.id == model.list.selection,
                    hotkey: model.list.hotkeyNumber(for: item.id))
                .equatable()
                .id(item.id)
                .onTapGesture { model.paste(id: item.id, plainText: false) }
        }
    }

    private var emptyState: some View {
        Text(model.isSearching ? "No matches" : "Nothing copied yet")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: model.captureState == .pausedByUser ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.captureState == .pausedByUser ? Color.secondary : Color.orange)
            if model.captureState == .pausedByUser {
                Text("Capture is paused")
                Spacer(minLength: 4)
                Button("Resume") { model.resumeCapture() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .focusable(false)
            } else {
                Text("Clipt can't see new copies — allow it in Privacy & Security → Paste from Other Apps")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 9, style: .continuous))
        .padding([.horizontal, .top], 6)
    }

    // MARK: Keys

    /// Runs before the search field sees the key, so ↑ ↓ ↩ never move its caret or submit.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let key: PanelKey
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .return: key = .enter
        // The ⌫ key reports U+007F; `KeyEquivalent.delete` is U+0008. Take either.
        case .delete, KeyEquivalent("\u{7F}"): key = .backspace
        case .escape: key = .escape
        default:
            guard let c = press.characters.first else { return .ignored }
            key = .character(c)
        }
        let command = press.modifiers.contains(.command)
        guard let action = PanelCommand.resolve(key, command: command, option: press.modifiers.contains(.option),
                                                queryIsEmpty: model.query.isEmpty) else {
            // Typing always lands in the search field, even if something else had focus.
            if !searchFocused, !command, !press.modifiers.contains(.control),
               case .character(let c) = key, !c.isNewline, c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
               c.unicodeScalars.first.map({ $0.value < 0xF700 || $0.value > 0xF8FF }) ?? false {
                searchFocused = true
                model.query.append(press.characters)
                return .handled
            }
            return .ignored
        }
        switch action {
        case .move(let d): model.move(by: d)
        case .paste(let plain): model.pasteSelected(plainText: plain)
        case .pasteHotkey(let n): model.paste(hotkey: n)
        case .togglePin: model.togglePin()
        case .delete: model.deleteSelected()
        case .escape: if model.escape() { model.close() }
        }
        return .handled
    }
}
