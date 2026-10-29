import AppKit
import Combine
import CliptCore

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

    /// Set by the controller: the app to paste into, read before `close` clears it.
    var pasteTarget: () -> NSRunningApplication? = { nil }
    var close: () -> Void = {}

    private var debounceTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Every reload bumps it; results from an older one are dropped.
    private var generation = 0
    private var previewedID: Int64?
    /// A reset that has not landed yet. A later reload (say, a copy arriving just after
    /// show) supersedes the task but must not drop the reset.
    private var resetPending = false
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
        debounceTask?.cancel()
        // Assigning the same value does not schedule a reload (didSet compares).
        query = ""
        filter = .all
        debounceTask?.cancel()
        if let first = list.recent.first ?? list.pinned.first { list.select(first.id) }
        focusRequest += 1
        reload(resetSelection: true)
    }

    /// Let go of everything that grows while browsing: deep pages, the preview image, thumbnails.
    func didHide() {
        debounceTask?.cancel()
        pageTask?.cancel(); pageTask = nil
        previewTask?.cancel(); previewTask = nil
        generation += 1
        preview = nil
        meta = nil
        previewedID = nil
        if list.recent.count > PanelList.pageSize {
            list.replace(pinned: list.pinned, recent: Array(list.recent.prefix(PanelList.pageSize)), resetSelection: true)
        }
        Thumbnails.removeAll()
    }

    // MARK: Loading

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.reload(resetSelection: true)
        }
    }

    func reload(resetSelection: Bool) {
        debounceTask?.cancel()
        reloadTask?.cancel()
        pageTask?.cancel(); pageTask = nil
        generation += 1
        let gen = generation
        let reset = resetSelection || resetPending
        resetPending = reset
        let q = trimmedQuery
        let f = filter
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
            self.list = next
            self.hasLoaded = true
        }
    }

    private func listDidChange() {
        if list.selection != previewedID { loadPreview() }
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
            self.list.appendPage(more)
        }
    }

    // MARK: Preview

    private func loadPreview() {
        previewTask?.cancel()
        previewTask = nil
        guard let item = selectedItem else {
            previewedID = nil; preview = nil; meta = nil
            return
        }
        previewedID = item.id
        // Something right away from what the row already has; the full content follows.
        let source = item.sourceAppName ?? "Unknown app"
        func setMeta(characters: Int? = nil, files: Int? = nil) {
            meta = PreviewMeta(source: source, copiedAt: item.copiedAt,
                               type: PanelFormat.typeLine(kind: item.kind, characters: characters,
                                                          byteSize: item.byteSize, fileCount: files))
        }
        setMeta()
        let id = item.id
        switch item.kind {
        case .text, .link:
            preview = .text(item.preview)
            previewTask = Task { [weak self] in
                guard let full = await History.shared.fullText(of: id) else { return }
                // Counting a multi-megabyte string is not main-thread work.
                let (shown, count) = await Task.detached(priority: .userInitiated) {
                    (String(full.prefix(PanelFormat.previewCharacterLimit)), full.count)
                }.value
                guard let self, !Task.isCancelled, self.previewedID == id else { return }
                self.preview = .text(shown)
                setMeta(characters: count)
            }
        case .color:
            let hex = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if let c = PanelFormat.hexColor(hex) {
                preview = .color(NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha), hex)
            } else {
                preview = .text(hex)
            }
        case .image:
            preview = item.thumbnailURL.flatMap { Thumbnails.image(at: $0, maxPixel: 256) }.map(PreviewContent.image)
            previewTask = Task { [weak self] in
                // Only once the selection rests: holding ↓ over images must not queue big reads.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let reps = await History.shared.representations(of: id)
                guard !Task.isCancelled,
                      let data = (reps.first { $0.type == PasteType.png } ?? reps.first { $0.type == PasteType.tiff })?.data
                else { return }
                let cg = await Task.detached(priority: .userInitiated) { Thumbnails.downsample(data, maxPixel: 900) }.value
                guard let self, let cg, !Task.isCancelled, self.previewedID == id else { return }
                self.preview = .image(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
        case .file:
            preview = .files([])
            previewTask = Task { [weak self] in
                let reps = await History.shared.representations(of: id)
                let urls = reps.filter { $0.type == PasteType.fileURL }
                    .compactMap { String(data: $0.data, encoding: .utf8).flatMap(URL.init(string:)) }
                guard let self, !Task.isCancelled, self.previewedID == id else { return }
                self.preview = .files(urls)
                setMeta(files: urls.count)
            }
        }
    }

    // MARK: Actions

    func move(by delta: Int) { list.moveSelection(by: delta) }
    func select(_ id: Int64) { list.select(id) }

    func pasteSelected(plainText: Bool) {
        guard let id = list.selection else { return }
        paste(id: id, plainText: plainText)
    }

    func paste(hotkey n: Int) {
        guard let item = list.item(forHotkey: n) else { return }
        paste(id: item.id, plainText: false)
    }

    /// Target first: hiding clears it.
    func paste(id: Int64, plainText: Bool) {
        let target = pasteTarget()
        close()
        Task { await Paster.paste(itemID: id, plainText: plainText, into: target) }
    }

    func togglePin() {
        guard let item = selectedItem else { return }
        History.shared.setPinned(item.id, !item.isPinned)
    }

    /// Gone from the list at once; the store catches up and the revision reload confirms it.
    func deleteSelected() {
        guard let id = list.selection else { return }
        list.remove(id)
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
