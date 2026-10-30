import SwiftUI
import CliptCore

/// The whole panel: search row, then list | preview, on one sheet of Liquid Glass.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool
    @Namespace private var glide

    private static let topID = "panel-top"
    private static let highlightID = "selection-highlight"
    /// One list row; ClipRow and the insert/remove transition both use it.
    static let rowHeight: CGFloat = 24
    /// The list's inset from the panel edges and the search row.
    private static let listPadding: CGFloat = 5

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                SearchRow(query: $model.query, filter: $model.filter, focused: $searchFocused)
                Rectangle().fill(.primary.opacity(0.1)).frame(height: 0.5)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if model.captureState != .active { banner }
                        list
                    }
                    .frame(width: PanelPlacement.size.width * 0.56)
                    // A held ↓ swaps the preview outright (a crossfade per repeat would only stack up),
                    // and so does the first fill while the panel opens.
                    PreviewPane(content: model.preview, meta: model.meta, itemID: model.list.selection,
                                crossfade: model.selectionCause != .keyRepeat && model.isSettledOpen)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: PanelPlacement.size.width, height: PanelPlacement.size.height)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .onChange(of: model.focusRequest, initial: true) { searchFocused = true }
    }

    // MARK: List

    private var list: some View {
        let style = Motion.style
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: Self.listPadding).id(Self.topID)
                    let showHeaders = !model.list.pinned.isEmpty
                    if showHeaders { SectionHeader(title: "Pinned").transition(.opacity) }
                    rows(model.list.pinned, style: style)
                    if showHeaders { SectionHeader(title: "Recent").transition(.opacity) }
                    rows(model.list.recent, style: style)
                    Color.clear.frame(height: Self.listPadding)
                }
                .padding(.horizontal, Self.listPadding)
            }
            .scrollIndicators(.automatic)
            .overlay { if model.hasLoaded && model.list.rows.isEmpty { emptyState } }
            .onChange(of: model.list.selection) { _, id in
                guard let id else { return }
                // A single step scrolls on the selection's spring; a held key, a reload or a
                // show scrolls at once, so nothing queues behind the repeat.
                let animated = model.selectionCause == .keyStep
                    && PanelMotion.animatesScroll(isKeyRepeat: false, style: Motion.style)
                var t = Transaction(animation: animated ? Motion.spring : nil)
                t.disablesAnimations = !animated
                withTransaction(t) {
                    // The first row brings its section header along.
                    if id == model.list.rows.first?.id { proxy.scrollTo(Self.topID, anchor: .top) }
                    else { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func rows(_ items: [ClipItem], style: MotionStyle) -> some View {
        ForEach(items) { item in
            let selected = item.id == model.list.selection
            let pulsed = model.pulse.id == item.id
            ClipRow(item: item, selected: selected, hotkey: model.list.hotkeyNumber(for: item.id))
                .equatable()
                .background {
                    // One highlight, handed from row to row: it glides instead of jumping.
                    if selected {
                        SelectionHighlight()
                            .modifier(GlideModifier(id: Self.highlightID, namespace: glide, enabled: style.moves))
                    }
                }
                // Every row runs the keyframes on a paste; only the pasted one applies them.
                .keyframeAnimator(initialValue: 1.0, trigger: model.pulse) { row, scale in
                    row.scaleEffect(pulsed ? scale : 1)
                } keyframes: { _ in
                    // Up: a cubic that lands exactly on 1.02 by the time the close starts (a 0.38 s
                    // spring cut at 50 ms would barely leave 1). Back: the pop spring, carrying that speed.
                    CubicKeyframe(PanelMotion.pulseScale, duration: PanelMotion.pulseLead)
                    SpringKeyframe(1.0, spring: Motion.Spring.pop.swiftUI)
                }
                // Pin and unpin: the row leaves one section and arrives in the other under one id, so it slides across.
                .modifier(GlideModifier(id: item.id, namespace: glide, enabled: style.moves, properties: .position))
                .transition(.listRow(height: Self.rowHeight, moves: style.moves))
                .id(item.id)
                .onTapGesture { model.paste(id: item.id, plainText: false) }
        }
    }

    private var emptyState: some View {
        Text(model.isSearching ? "No matches" : "Nothing copied yet")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: model.captureState == .pausedByUser ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.captureState == .pausedByUser ? Color.secondary : Color.orange)
            if model.captureState == .pausedByUser {
                Text("Capture is paused")
                Spacer(minLength: 4)
                Button("Resume") { model.resumeCapture() }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                    .focusable(false)
            } else {
                Text("Clipt can't see new copies — allow it in Privacy & Security → Paste from Other Apps")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
        .padding([.horizontal, .top], Self.listPadding)
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
        let isRepeat = press.phase == .repeat
        // KeyPress has no key code; the NSEvent being dispatched does. ⌘1–⌘9 go by physical
        // key so they work on AZERTY, where the number row types & é " ' ( § è ! ç.
        let event = NSApp.currentEvent
        let keyCode = event?.type == .keyDown ? event?.keyCode : nil
        guard let action = PanelCommand.resolve(key, command: command, option: press.modifiers.contains(.option),
                                                queryIsEmpty: model.query.isEmpty,
                                                keyCode: keyCode, isRepeat: isRepeat) else {
            // A held key the panel ignores (⌫, letters) goes to the field, which repeats it itself.
            if isRepeat { return .ignored }
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
        case .move(let d): model.move(by: d, repeating: isRepeat)
        case .paste(let plain): model.pasteSelected(plainText: plain)
        case .pasteHotkey(let n): model.paste(hotkey: n)
        case .togglePin: model.togglePin()
        case .delete: model.deleteSelected()
        case .escape: if model.escape() { model.close() }
        }
        return .handled
    }
}
