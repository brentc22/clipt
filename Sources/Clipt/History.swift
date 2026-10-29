import AppKit
import Combine
import CliptCore
import ImageIO
import os

/// ClipStore is not thread-safe and not Sendable. Every access goes through `queue`;
/// the box exists only to carry the reference across that boundary.
private final class StoreBox: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.brentc22.Clipt.store", qos: .userInitiated)
    private var store: ClipStore?   // touched only on `queue`

    func open(_ directory: URL) {
        queue.async {
            do { self.store = try ClipStore(directory: directory) }
            catch { Logger(subsystem: "com.brentc22.Clipt", category: "history").error("cannot open store: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Runs on the store queue. Nil if the store failed to open or `work` threw.
    func run<T: Sendable>(_ work: @escaping @Sendable (ClipStore) throws -> T) async -> T? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let store = self.store else { return cont.resume(returning: nil) }
                do { cont.resume(returning: try work(store)) }
                catch {
                    Logger(subsystem: "com.brentc22.Clipt", category: "history").error("store error: \(error.localizedDescription, privacy: .public)")
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

/// The one owner of the clip store, and what the panel and menus talk to.
@MainActor
final class History: ObservableObject {
    static let shared = History()

    @Published private(set) var captureState: CaptureState = .active
    /// Bumps after every change; the panel reloads on it.
    @Published private(set) var revision = 0

    private let box = StoreBox()
    private var monitor: PasteboardMonitor?
    private var ownWrites = OwnWriteTracker()
    private var started = false

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipt", isDirectory: true)
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        box.open(Self.directory)
        let policy = Prefs.shared.retention
        Task { [box] in
            _ = await box.run { try $0.enforce(policy) }
            self.bump()
        }
        let m = PasteboardMonitor(history: self)
        monitor = m
        m.start()
    }

    func stop() { monitor?.stop() }

    /// Re-evaluates capture state now, e.g. after the pause preference changed.
    func refreshCaptureState() { monitor?.refreshState() }

    // MARK: Reading

    func recent(filter: KindFilter, limit: Int, offset: Int) async -> [ClipItem] {
        await box.run { try $0.recent(filter: filter, limit: limit, offset: offset) } ?? []
    }

    func search(_ q: String, filter: KindFilter) async -> (pinned: [ClipItem], recent: [ClipItem]) {
        await box.run { try $0.search(q, filter: filter, limit: 200) } ?? ([], [])
    }

    func pinned(filter: KindFilter) async -> [ClipItem] {
        await box.run { try $0.pinned(filter: filter) } ?? []
    }

    func representations(of id: Int64) async -> [Representation] {
        await box.run { try $0.representations(of: id) } ?? []
    }

    func fullText(of id: Int64) async -> String? {
        await box.run { try $0.fullText(of: id) } ?? nil
    }

    // MARK: Changing

    func setPinned(_ id: Int64, _ on: Bool) { mutate { try $0.setPinned(id, on) } }
    func delete(_ id: Int64) { mutate { try $0.delete(id) } }
    func clearHistory() { mutate { try $0.clearHistory() } }
    func touch(_ id: Int64) { mutate { try $0.touch(id) } }

    /// Called by the paster after it writes an item back, so the monitor bumps it
    /// instead of capturing the write as a new copy.
    func didWriteOwn(changeCount: Int, itemID: Int64) {
        ownWrites.recordWrite(changeCount: changeCount, itemID: itemID)
    }

    func claimOwnWrite(changeCount: Int) -> Int64? { ownWrites.claim(changeCount: changeCount) }

    func setCaptureState(_ s: CaptureState) {
        if captureState != s { captureState = s }
    }

    // MARK: Capture

    func capture(_ snapshot: PasteboardSnapshot, sourceBundleID: String?, sourceAppName: String?) {
        let policy = Prefs.shared.retention
        Task { [box] in
            let result: (id: Int64, kind: ClipKind, image: Data?)? = await box.run { store in
                guard let content = ClipClassifier.content(from: snapshot) else { return nil }
                let item = try store.insert(content, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName)
                try store.enforce(policy)
                let image = content.kind == .image
                    ? (content.representations.first { $0.type == PasteType.png } ?? content.representations.first { $0.type == PasteType.tiff })?.data
                    : nil
                return (item.id, item.kind, image)
            } ?? nil
            self.bump()
            if let result, let data = result.image { self.recognize(data, for: result.id) }
        }
    }

    /// OCR at utility priority; the text lands in the search index when it is done.
    private func recognize(_ data: Data, for id: Int64) {
        Task.detached(priority: .utility) { [box] in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            let text = await TextRecognizer.text(in: image)
            guard !text.isEmpty else { return }
            _ = await box.run { try $0.setRecognizedText(text, for: id) }
            await self.bump()
        }
    }

    private func mutate(_ work: @escaping @Sendable (ClipStore) throws -> Void) {
        Task { [box] in
            _ = await box.run(work)
            self.bump()
        }
    }

    private func bump() { revision += 1 }
}
