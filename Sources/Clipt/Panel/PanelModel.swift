import AppKit
import Combine
import QuartzCore
import SwiftUI
import CliptCore

/// The panel's state. Data comes from `History`; the view only reads this and calls methods.
@MainActor
final class PanelModel: ObservableObject {
    @Published private(set) var list = PanelList(pinned: [], recent: []) {
        didSet { listDidChange() }
    }
    @Published var query = "" {
        didSet { if query != oldValue { scheduleReload() } }
    }
    @Published var filter: KindFilter = .all {
        didSet { if filter != oldValue { scheduleReload() } }
    }
    @Published private(set) var preview: PreviewContent?
    @Published private(set) var meta: PreviewMeta?
    @Published private(set) var captureState: CaptureState = .active
    /// False until the first load lands, so the empty state never flashes on launch.
    @Published private(set) var hasLoaded = false
    /// Bumped on every show; the view focuses the search field when it changes.
    @Published private(set) var focusRequest = 0
    /// Bumped on each paste; the row with `pulse.id` plays its pulse when it changes.
    @Published private(set) var pulse = PastePulse(id: nil, count: 0)
    /// What last moved the selection. Read by the view while it updates for that move:
    /// a held key must not animate the scroll or crossfade the preview.
    private(set) var selectionCause = SelectionCause.other

    /// Set by the controller: the app to paste into, read before `close` clears it.
    var pasteTarget: () -> NSRunningApplication? = { nil }
    var close: () -> Void = {}
    /// Closes the panel for a paste and runs the closure once focus is back in the target.
    var closeForPaste: (@escaping () -> Void) -> Void = { $0() }
    /// Set by the controller: the panel is on its way out (Esc, hotkey, focus loss, paste).
    var isClosing: () -> Bool = { false }

    private var debounceTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    /// Every reload bumps it; results from an older one are dropped.
    private var generation = 0
    private let previewLoader = PreviewLoader()
    /// A reset that has not landed yet. A later reload (say, a copy arriving just after
    /// show) supersedes the task but must not drop the reset.
    private var resetPending = false
    /// What the list on screen was loaded for. A load for anything else always resets.
    private var loadedQuery: String?
    private var loadedFilter: KindFilter?
    /// A query/filter change is waiting out its debounce.
    private var reloadDue = false
    /// Bumped on every show and hide, so a paste that waited for results can tell the panel closed meanwhile.
    private var session = 0
    private var pastePending = false
    /// A paste is under way: the pulse and close are running and a second ↩ must not paste again.
    private var pasting = false
    /// When this session's panel went on screen, and whether its first load is in.
    private var shownAt: CFTimeInterval?
    private var initialLoadLanded = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        History.shared.$captureState
            .sink { [weak self] in self?.captureState = $0 }
            .store(in: &cancellables)
        History.shared.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.reload(resetSelection: false) }
            .store(in: &cancellables)
    }

    var selectedItem: ClipItem? {
        guard let id = list.selection else { return nil }
        return list.rows.first { $0.id == id }
    }

    var isSearching: Bool { !trimmedQuery.isEmpty || filter != .all }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Showing and hiding

    /// Synchronous and cheap: the panel goes on screen in the same turn, the data follows.
    func willShow() {
        session += 1
        pastePending = false
        pasting = false
        shownAt = CACurrentMediaTime()
        initialLoadLanded = false
        selectionCause = .other
        debounceTask?.cancel()
        // Assigning the same value does not schedule a reload (didSet compares).
        query = ""
        filter = .all
        debounceTask?.cancel()
        if let first = list.recent.first ?? list.pinned.first { list.select(first.id) }
        focusRequest += 1
        reload(resetSelection: true)
    }

    /// Let go of everything that grows while browsing: deep pages and the preview image.
    /// Row thumbnails stay in their byte-bounded cache, so they don't flicker on the next open.
    func didHide() {
        session += 1
        shownAt = nil
        reloadDue = false
        debounceTask?.cancel()
        reloadTask?.cancel(); reloadTask = nil
        pageTask?.cancel(); pageTask = nil
        previewLoader.cancel()
        generation += 1
        preview = nil
        meta = nil
        if list.recent.count > PanelList.pageSize {
            list.replace(pinned: list.pinned, recent: Array(list.recent.prefix(PanelList.pageSize)), resetSelection: true)
        }
    }

    // MARK: Loading

    private func scheduleReload() {
        reloadDue = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.reload(resetSelection: true)
        }
    }

    func reload(resetSelection: Bool) {
        reloadDue = false
        debounceTask?.cancel()
        reloadTask?.cancel()
        pageTask?.cancel(); pageTask = nil
        generation += 1
        let gen = generation
        let q = trimmedQuery
        let f = filter
        // A revision reload that supersedes a debounced one still carries its reset.
        let reset = resetSelection || resetPending || q != loadedQuery || f != loadedFilter
        resetPending = reset
        // Keep what was paged in, so a background change never yanks a deep selection to the top.
        let limit = reset ? PanelList.pageSize : max(PanelList.pageSize, list.recent.count)
        reloadTask = Task { [weak self] in
            let history = History.shared
            let pinned: [ClipItem], recent: [ClipItem]
            if q.isEmpty {
                pinned = await history.pinned(filter: f)
                recent = await history.recent(filter: f, limit: limit, offset: 0)
            } else {
                (pinned, recent) = await history.search(q, filter: f)
            }
            guard let self, gen == self.generation else { return }
            var next = self.list
            next.replace(pinned: pinned, recent: recent, resetSelection: reset)
            self.resetPending = false
            if !q.isEmpty { next.markExhausted() }   // search results come in one piece
            self.loadedQuery = q
            self.loadedFilter = f
            self.reloadTask = nil
            self.selectionCause = .other
            // The first load of a show lands as is; later changes (a copy arriving, a pin, a search) reflow.
            self.withListAnimation { self.list = next }
            self.initialLoadLanded = true
            self.hasLoaded = true
        }
    }

    /// Waits until the list on screen matches the query and filter as typed: a debounce
    /// still waiting is run now, and any reload in flight is awaited.
    private func settle() async {
        if reloadDue { reload(resetSelection: true) }
        while let task = reloadTask {
            await task.value
            if reloadTask == task { break }   // ended without landing (hidden); nothing newer is coming
        }
    }

    private var isSettled: Bool { !reloadDue && reloadTask == nil }

    /// The panel is on screen, its first load is in and it has finished opening: changes may animate.
    var isSettledOpen: Bool {
        PanelMotion.isSettledOpen(visible: shownAt != nil, initialLoadLanded: initialLoadLanded,
                                  secondsSinceShow: secondsSinceShow)
    }
    private var secondsSinceShow: Double { shownAt.map { CACurrentMediaTime() - $0 } ?? 0 }

    /// Runs `change` under `Motion.spring` only once the panel is open and settled, and never
    /// in fades-only mode, where the change lands at once.
    private func withListAnimation(_ change: () -> Void) {
        let animates = PanelMotion.animatesListChanges(style: Motion.style, visible: shownAt != nil,
                                                       initialLoadLanded: initialLoadLanded,
                                                       secondsSinceShow: secondsSinceShow)
        if animates { withAnimation(Motion.spring, change) } else { change() }
    }

    private func listDidChange() {
        if list.selection != previewLoader.itemID {
            previewLoader.load(selectedItem) { [weak self] content, meta in
                self?.preview = content
                self?.meta = meta
            }
        }
        if list.needsNextPage { loadNextPage() }
    }

    private func loadNextPage() {
        guard pageTask == nil, trimmedQuery.isEmpty else { return }
        let gen = generation
        let f = filter
        let offset = list.recent.count
        pageTask = Task { [weak self] in
            let more = await History.shared.recent(filter: f, limit: PanelList.pageSize, offset: offset)
            guard let self, gen == self.generation else { return }
            self.pageTask = nil
            self.selectionCause = .other
            self.list.appendPage(more)
        }
    }

    // MARK: Actions

    /// The highlight glides on a spring that retargets; a held key gets the stiff one.
    func move(by delta: Int, repeating: Bool) {
        selectionCause = repeating ? .keyRepeat : .keyStep
        withAnimation(Motion.selection(repeating: repeating)) { list.moveSelection(by: delta) }
    }
    func select(_ id: Int64) {
        selectionCause = .other
        list.select(id)
    }

    /// ↩ right after typing must paste from the results for what was typed, not from the
    /// list still on screen: resolve the row only once the list has caught up.
    func pasteSelected(plainText: Bool) {
        whenSettled { $0.list.selection.map { ($0, plainText) } }
    }

    /// ⌘N likewise pastes the row showing ⌘N in the settled list.
    func paste(hotkey n: Int) {
        whenSettled { $0.list.item(forHotkey: n).map { ($0.id, false) } }
    }

    private func whenSettled(_ pick: @escaping (PanelModel) -> (Int64, Bool)?) {
        guard !pastePending, PanelMotion.allowsPaste(isClosing: isClosing(), isPasting: pasting) else { return }
        if isSettled {
            if let (id, plain) = pick(self) { paste(id: id, plainText: plain) }
            return
        }
        pastePending = true
        let mine = session
        Task { [weak self] in
            await self?.settle()
            guard let self, self.session == mine else { return }   // closed while waiting
            self.pastePending = false
            if let (id, plain) = pick(self) { self.paste(id: id, plainText: plain) }
        }
    }

    /// Target first: hiding clears it. The row pulses, the panel closes, and the paste starts
    /// as soon as the panel is off screen (at most `PanelMotion.pasteStartDelay` after ↩).
    func paste(id: Int64, plainText: Bool) {
        // Closing: the target is already cleared, so a paste now would write the pasteboard and go nowhere.
        guard PanelMotion.allowsPaste(isClosing: isClosing(), isPasting: pasting) else { return }
        pasting = true
        let target = pasteTarget()
        let closeAndPaste = { [weak self] in
            guard let self else { return }
            self.closeForPaste { Task { await Paster.paste(itemID: id, plainText: plainText, into: target) } }
        }
        guard Motion.style.pulsesOnPaste else { return closeAndPaste() }
        withAnimation(nil) { pulse = PastePulse(id: id, count: pulse.count + 1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelMotion.pulseLead) {
            // Hidden meanwhile (focus moved away): closeForPaste pastes at once, as it always did.
            MainActor.assumeIsolated { closeAndPaste() }
        }
    }

    func togglePin() {
        guard let item = selectedItem else { return }
        History.shared.setPinned(item.id, !item.isPinned)
    }

    /// Gone from the list at once; the store catches up and the revision reload confirms it.
    func deleteSelected() {
        guard let id = list.selection else { return }
        selectionCause = .other
        withListAnimation { list.remove(id) }
        History.shared.delete(id)
    }

    /// Clears the search first; true when the panel should close.
    func escape() -> Bool {
        guard query.isEmpty else {
            query = ""
            return false
        }
        return true
    }

    func resumeCapture() {
        Prefs.shared.capturePaused = false
        History.shared.refreshCaptureState()
    }
}

/// Which row should pulse for the latest paste; `count` makes each paste a new value.
struct PastePulse: Equatable {
    let id: Int64?
    let count: Int
}

enum SelectionCause {
    case keyStep, keyRepeat, other
}
