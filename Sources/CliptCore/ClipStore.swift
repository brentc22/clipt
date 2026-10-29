import Foundation
import CryptoKit
import SQLite3

public struct ClipItem: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipKind
    public let preview: String
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let copiedAt: Date
    public let isPinned: Bool
    public let byteSize: Int
    /// Images only, at most 256 px PNG.
    public let thumbnailURL: URL?
}

/// Chip order. `.text` matches text, color and file.
public enum KindFilter: String, Sendable, CaseIterable {
    case all, text, images, links

    fileprivate var sql: String {
        switch self {
        case .all: "1"
        case .text: "items.kind IN ('text','color','file')"
        case .images: "items.kind = 'image'"
        case .links: "items.kind = 'link'"
        }
    }
}

/// Not thread-safe: the app owns one on a serial queue.
public final class ClipStore {
    /// Only this many leading characters of a text go into the search index.
    static let indexedCharacterLimit = 100_000

    private let db: Database
    private let directory: URL
    private let blobsDir: URL
    private let thumbsDir: URL

    private static let columns = "items.id, items.kind, items.preview, items.source_bundle, items.source_name, items.copied_at, items.pinned_at, items.byte_size, items.thumb"

    public init(directory: URL) throws {
        let fm = FileManager.default
        self.directory = directory
        blobsDir = directory.appendingPathComponent("blobs", isDirectory: true)
        thumbsDir = directory.appendingPathComponent("thumbs", isDirectory: true)
        try fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("clipt.sqlite").path
        do {
            db = try Self.open(path)
        } catch let e as SQLiteError where e.code == SQLITE_NOTADB || e.code == SQLITE_CORRUPT {
            let stamp = Int(Date().timeIntervalSince1970)
            for suffix in ["", "-wal", "-shm"] {
                let from = path + suffix
                guard fm.fileExists(atPath: from) else { continue }
                let to = suffix.isEmpty ? "\(path).corrupt-\(stamp)" : "\(path).corrupt-\(stamp)\(suffix)"
                try fm.moveItem(atPath: from, toPath: to)
            }
            db = try Self.open(path)
        }
    }

    private static func open(_ path: String) throws -> Database {
        let db = try Database(path: path)
        try db.exec("PRAGMA journal_mode = WAL")
        try db.exec("PRAGMA synchronous = NORMAL")
        try db.exec("""
            CREATE TABLE IF NOT EXISTS items(
                id INTEGER PRIMARY KEY, hash TEXT UNIQUE, kind TEXT, preview TEXT, plain_text TEXT,
                source_bundle TEXT, source_name TEXT, copied_at REAL, pinned_at REAL NULL,
                byte_size INTEGER, thumb TEXT NULL);
            CREATE INDEX IF NOT EXISTS items_order ON items(pinned_at, copied_at DESC);
            CREATE TABLE IF NOT EXISTS reps(item_id INTEGER, ord INTEGER, type TEXT, blob TEXT, size INTEGER);
            CREATE INDEX IF NOT EXISTS reps_item ON reps(item_id);
            CREATE INDEX IF NOT EXISTS reps_blob ON reps(blob);
            CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(plain_text, ocr_text, tokenize='unicode61 remove_diacritics 2');
            PRAGMA user_version = 1;
            """)
        return db
    }

    // MARK: Writes

    /// Runs `body` inside one transaction (for bulk inserts).
    public func batch(_ body: () throws -> Void) throws {
        try db.transaction(body)
    }

    @discardableResult
    public func insert(_ c: ClipContent, sourceBundleID: String?, sourceAppName: String?, at: Date = Date()) throws -> ClipItem {
        // Files first; an orphan blob after a failed transaction is harmless.
        var blobNames: [String] = []
        for rep in c.representations { blobNames.append(try writeBlob(rep.data)) }
        var thumbName: String?
        if c.kind == .image,
           let src = c.representations.first(where: { $0.type == PasteType.png || $0.type == PasteType.tiff }),
           let png = Thumbnailer.png(from: src.data) {
            let name = c.primaryHash + ".png"
            let url = thumbsDir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try png.write(to: url, options: .atomic) }
            thumbName = name
        }
        let id: Int64 = try db.transaction {
            let find = try db.prepare("SELECT id FROM items WHERE hash = ?")
            try find.bind([.text(c.primaryHash)])
            if try find.step() {
                let id = find.int64(0)
                try db.run("UPDATE items SET copied_at = ?, source_bundle = ?, source_name = ? WHERE id = ?",
                           [.double(at.timeIntervalSince1970), .optText(sourceBundleID), .optText(sourceAppName), .int(id)])
                return id
            }
            try db.run("""
                INSERT INTO items(hash, kind, preview, plain_text, source_bundle, source_name, copied_at, pinned_at, byte_size, thumb)
                VALUES(?,?,?,?,?,?,?,NULL,?,?)
                """, [.text(c.primaryHash), .text(c.kind.rawValue), .text(c.preview), .optText(c.plainText),
                      .optText(sourceBundleID), .optText(sourceAppName), .double(at.timeIntervalSince1970),
                      .int(Int64(c.byteSize)), .optText(thumbName)])
            let id = db.lastInsertRowID
            for (i, rep) in c.representations.enumerated() {
                try db.run("INSERT INTO reps(item_id, ord, type, blob, size) VALUES(?,?,?,?,?)",
                           [.int(id), .int(Int64(i)), .text(rep.type), .text(blobNames[i]), .int(Int64(rep.data.count))])
            }
            let indexed = c.plainText.map { String($0.prefix(Self.indexedCharacterLimit)) } ?? ""
            try db.run("INSERT INTO fts(rowid, plain_text, ocr_text) VALUES(?,?,'')", [.int(id), .text(indexed)])
            return id
        }
        guard let item = try item(id) else { throw SQLiteError(code: SQLITE_ERROR, message: "inserted item vanished") }
        return item
    }

    public func touch(_ id: Int64, at: Date = Date()) throws {
        try db.run("UPDATE items SET copied_at = ? WHERE id = ?", [.double(at.timeIntervalSince1970), .int(id)])
    }

    public func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try db.run("UPDATE items SET pinned_at = ? WHERE id = ?",
                   [.optDouble(pinned ? Date().timeIntervalSince1970 : nil), .int(id)])
    }

    public func setRecognizedText(_ text: String, for id: Int64) throws {
        try db.run("UPDATE fts SET ocr_text = ? WHERE rowid = ?", [.text(text), .int(id)])
    }

    public func delete(_ id: Int64) throws { try delete(ids: [id]) }

    public func clearHistory() throws {
        try delete(ids: try ids("SELECT id FROM items WHERE pinned_at IS NULL"))
    }

    public func enforce(_ policy: RetentionPolicy, now: Date = Date()) throws {
        var doomed = Set<Int64>()
        if let age = policy.maxAge {
            doomed.formUnion(try ids("SELECT id FROM items WHERE pinned_at IS NULL AND copied_at < ?",
                                     [.double(now.timeIntervalSince1970 - age)]))
        }
        if let max = policy.maxItems {
            doomed.formUnion(try ids("SELECT id FROM items WHERE pinned_at IS NULL ORDER BY copied_at DESC, id DESC LIMIT -1 OFFSET ?",
                                     [.int(Int64(max))]))
        }
        try delete(ids: Array(doomed))
    }

    private func ids(_ sql: String, _ binds: [Bind] = []) throws -> [Int64] {
        let s = try db.prepare(sql)
        try s.bind(binds)
        var out: [Int64] = []
        while try s.step() { out.append(s.int64(0)) }
        return out
    }

    private func delete(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        var candidates = Set<String>()
        var thumbs = Set<String>()
        try db.transaction {
            for id in ids {
                let r = try db.prepare("SELECT blob FROM reps WHERE item_id = ?")
                try r.bind([.int(id)])
                while try r.step() { candidates.insert(r.text(0)) }
                let t = try db.prepare("SELECT thumb FROM items WHERE id = ?")
                try t.bind([.int(id)])
                if try t.step(), let name = t.optText(0) { thumbs.insert(name) }
                try db.run("DELETE FROM reps WHERE item_id = ?", [.int(id)])
                try db.run("DELETE FROM fts WHERE rowid = ?", [.int(id)])
                try db.run("DELETE FROM items WHERE id = ?", [.int(id)])
            }
        }
        let fm = FileManager.default
        for name in candidates {
            let q = try db.prepare("SELECT 1 FROM reps WHERE blob = ? LIMIT 1")
            try q.bind([.text(name)])
            if try !q.step() { try? fm.removeItem(at: blobsDir.appendingPathComponent(name)) }
        }
        for name in thumbs {
            let q = try db.prepare("SELECT 1 FROM items WHERE thumb = ? LIMIT 1")
            try q.bind([.text(name)])
            if try !q.step() { try? fm.removeItem(at: thumbsDir.appendingPathComponent(name)) }
        }
    }

    private func writeBlob(_ data: Data) throws -> String {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = blobsDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name
    }

    // MARK: Reads

    public func count() throws -> Int {
        let s = try db.prepare("SELECT COUNT(*) FROM items")
        _ = try s.step()
        return Int(s.int64(0))
    }

    public func pinned(filter: KindFilter) throws -> [ClipItem] {
        try items("SELECT \(Self.columns) FROM items WHERE pinned_at IS NOT NULL AND \(filter.sql) ORDER BY pinned_at ASC, id ASC")
    }

    public func recent(filter: KindFilter, limit: Int, offset: Int) throws -> [ClipItem] {
        try items("SELECT \(Self.columns) FROM items WHERE pinned_at IS NULL AND \(filter.sql) ORDER BY copied_at DESC, id DESC LIMIT ? OFFSET ?",
                  [.int(Int64(limit)), .int(Int64(offset))])
    }

    public func search(_ query: String, filter: KindFilter, limit: Int) throws -> (pinned: [ClipItem], recent: [ClipItem]) {
        let terms = query.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        guard !terms.isEmpty else {
            return (try pinned(filter: filter), try recent(filter: filter, limit: limit, offset: 0))
        }
        let match = terms.joined(separator: " AND ")
        let base = "SELECT \(Self.columns) FROM fts JOIN items ON items.id = fts.rowid WHERE fts MATCH ? AND \(filter.sql)"
        let pins = try items(base + " AND items.pinned_at IS NOT NULL ORDER BY items.pinned_at ASC, items.id ASC", [.text(match)])
        let rest = try items(base + " AND items.pinned_at IS NULL ORDER BY items.copied_at DESC, items.id DESC LIMIT ?",
                             [.text(match), .int(Int64(limit))])
        return (pins, rest)
    }

    public func representations(of id: Int64) throws -> [Representation] {
        let s = try db.prepare("SELECT type, blob FROM reps WHERE item_id = ? ORDER BY ord")
        try s.bind([.int(id)])
        var out: [Representation] = []
        while try s.step() {
            guard let data = try? Data(contentsOf: blobsDir.appendingPathComponent(s.text(1))) else { continue }
            out.append(Representation(type: s.text(0), data: data))
        }
        return out
    }

    public func fullText(of id: Int64) throws -> String? {
        let s = try db.prepare("SELECT plain_text FROM items WHERE id = ?")
        try s.bind([.int(id)])
        return try s.step() ? s.optText(0) : nil
    }

    private func item(_ id: Int64) throws -> ClipItem? {
        try items("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)]).first
    }

    private func items(_ sql: String, _ binds: [Bind] = []) throws -> [ClipItem] {
        let s = try db.prepare(sql)
        try s.bind(binds)
        var out: [ClipItem] = []
        while try s.step() {
            out.append(ClipItem(
                id: s.int64(0), kind: ClipKind(rawValue: s.text(1)) ?? .text, preview: s.text(2),
                sourceBundleID: s.optText(3), sourceAppName: s.optText(4),
                copiedAt: Date(timeIntervalSince1970: s.double(5)), isPinned: !s.isNull(6),
                byteSize: Int(s.int64(7)),
                thumbnailURL: s.optText(8).map { thumbsDir.appendingPathComponent($0) }))
        }
        return out
    }
}
