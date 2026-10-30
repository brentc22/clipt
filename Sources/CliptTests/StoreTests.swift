import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CliptCore
import SQLite3

func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("clipt-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func text(_ s: String) -> ClipContent {
    ClipClassifier.content(from: snap([("public.utf8-plain-text", s)]))!
}

func imageData(width: Int = 4, height: Int = 4, type: UTType = .png, orientation: Int? = nil) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
    let props = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func imageContent(width: Int = 4, height: Int = 4) -> ClipContent {
    let data = imageData(width: width, height: height)
    return ClipClassifier.content(from: .init(representations: [.init(type: PasteType.png, data: data)]))!
}

func storeTests() {
    print("Store")
    T.test("newest first, duplicates move to the top") {
        let s = try ClipStore(directory: tmp()); let t0 = Date(timeIntervalSince1970: 1000)
        try s.insert(text("a"), sourceBundleID: nil, sourceAppName: nil, at: t0)
        try s.insert(text("b"), sourceBundleID: nil, sourceAppName: nil, at: t0 + 1)
        try s.insert(text("a"), sourceBundleID: nil, sourceAppName: nil, at: t0 + 2)
        T.equal(try s.recent(filter: .all, limit: 50, offset: 0).map(\.preview), ["a", "b"]); T.equal(try s.count(), 2)
    }
    T.test("touch moves to top and keeps the source app") {
        let s = try ClipStore(directory: tmp())
        let a = try s.insert(text("a"), sourceBundleID: "com.apple.Safari", sourceAppName: "Safari", at: .init(timeIntervalSince1970: 1))
        try s.insert(text("b"), sourceBundleID: nil, sourceAppName: nil, at: .init(timeIntervalSince1970: 2))
        try s.touch(a.id, at: .init(timeIntervalSince1970: 3))
        let top = try s.recent(filter: .all, limit: 1, offset: 0)[0]
        T.equal(top.preview, "a"); T.equal(top.sourceAppName, "Safari")
    }
    T.test("pins are separate, survive clear and retention") {
        let s = try ClipStore(directory: tmp()); let p = try s.insert(text("pin me"), sourceBundleID: nil, sourceAppName: nil)
        try s.setPinned(p.id, true); for i in 0..<5 { try s.insert(text("x\(i)"), sourceBundleID: nil, sourceAppName: nil) }
        try s.enforce(.init(maxItems: 2, maxAge: nil))
        T.equal(try s.recent(filter: .all, limit: 50, offset: 0).count, 2); T.equal(try s.pinned(filter: .all).map(\.preview), ["pin me"])
        try s.clearHistory(); T.equal(try s.count(), 1)
    }
    T.test("age retention") {
        let s = try ClipStore(directory: tmp()); let now = Date()
        try s.insert(text("old"), sourceBundleID: nil, sourceAppName: nil, at: now - 8 * 86_400)
        try s.insert(text("new"), sourceBundleID: nil, sourceAppName: nil, at: now)
        try s.enforce(.init(maxItems: nil, maxAge: 604_800), now: now)
        T.equal(try s.recent(filter: .all, limit: 50, offset: 0).map(\.preview), ["new"])
    }
    T.test("search: prefix, diacritics, filter, OCR text") {
        let s = try ClipStore(directory: tmp())
        try s.insert(text("https://github.com/brentc22/clipt"), sourceBundleID: nil, sourceAppName: nil)
        try s.insert(text("Café crème"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(try s.search("brentc", filter: .all, limit: 50).recent.count, 1)
        T.equal(try s.search("cafe", filter: .all, limit: 50).recent.map(\.preview), ["Café crème"])
        T.equal(try s.search("brentc", filter: .text, limit: 50).recent.count, 0)       // it's a link
        let img = try s.insert(imageContent(), sourceBundleID: nil, sourceAppName: nil)
        try s.setRecognizedText("invoice 2026", for: img.id, hash: imageContent().primaryHash)
        T.equal(try s.search("invoice", filter: .images, limit: 50).recent.map(\.id), [img.id])
    }
    T.test("insert says whether the row is new, so a re-copy skips OCR") {
        let s = try ClipStore(directory: tmp())
        let first = try s.insertResult(imageContent(), sourceBundleID: nil, sourceAppName: nil)
        T.equal(first.isNew, true)
        let again = try s.insertResult(imageContent(), sourceBundleID: nil, sourceAppName: nil)
        T.equal(again.isNew, false)
        T.equal(again.item.id, first.item.id)
        T.equal(try s.insertResult(text("other"), sourceBundleID: nil, sourceAppName: nil).isNew, true)
    }
    T.test("late OCR does not land on an item that reused the id") {
        let s = try ClipStore(directory: tmp())
        let img = try s.insert(imageContent(), sourceBundleID: nil, sourceAppName: nil)
        try s.delete(img.id)
        let fresh = try s.insert(text("fresh note"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(fresh.id, img.id, "id reused")
        try s.setRecognizedText("lateocrword", for: img.id, hash: imageContent().primaryHash)
        T.equal(try s.search("lateocrword", filter: .all, limit: 50).recent.count, 0)
        T.equal(try s.search("fresh", filter: .all, limit: 50).recent.count, 1)
    }
    T.test("representations round-trip and blobs are cleaned on delete") {
        let dir = tmp(); let s = try ClipStore(directory: dir); let i = try s.insert(text("hi"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(try s.representations(of: i.id).first?.data, Data("hi".utf8)); try s.delete(i.id)
        T.equal(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("blobs").path).count, 0)
    }
    T.test("a corrupt database is moved aside, not fatal") {
        let d = tmp(); try Data("not a database".utf8).write(to: d.appendingPathComponent("clipt.sqlite"))
        let keep = d.appendingPathComponent("blobs/keepme")
        try FileManager.default.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: keep)
        let s = try ClipStore(directory: d); T.equal(try s.count(), 0)
        T.expect(try FileManager.default.contentsOfDirectory(atPath: d.path).contains { $0.hasPrefix("clipt.sqlite.corrupt-") }, "kept aside")
        T.expect(FileManager.default.fileExists(atPath: keep.path), "blobs untouched after recovery")
    }
    T.test("odd queries never throw; empty query equals pinned + recent") {
        let s = try ClipStore(directory: tmp())
        let p = try s.insert(text("pinned one"), sourceBundleID: nil, sourceAppName: nil)
        try s.setPinned(p.id, true)
        try s.insert(text("say \"hello\" there"), sourceBundleID: nil, sourceAppName: nil)
        for q in ["", "   ", "\"", "***", "-", "a OR", "(", "\"hello\""] { _ = try s.search(q, filter: .all, limit: 50) }
        let e = try s.search("  ", filter: .all, limit: 50)
        T.equal(e.pinned.map(\.preview), ["pinned one"]); T.equal(e.recent.count, 1)
        T.equal(try s.search("\"hello\"", filter: .all, limit: 50).recent.count, 1)
    }
    T.test("deleting an item removes it from search; thumbnails are small PNGs") {
        let s = try ClipStore(directory: tmp())
        let i = try s.insert(text("findme"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(try s.search("findme", filter: .all, limit: 5).recent.count, 1)
        try s.delete(i.id)
        T.equal(try s.search("findme", filter: .all, limit: 5).recent.count, 0)
        let img = try s.insert(imageContent(), sourceBundleID: nil, sourceAppName: nil)
        T.expect(img.thumbnailURL != nil, "thumbnail present")
    }
    T.test("pixel size: read from the header, rotation applied") {
        T.equal(Thumbnailer.pixelSize(of: imageData(width: 30, height: 20)), PixelSize(width: 30, height: 20))
        T.equal(Thumbnailer.pixelSize(of: imageData(width: 30, height: 20, type: .jpeg, orientation: 6)),
                PixelSize(width: 20, height: 30), "EXIF 6 turns it a quarter")
        T.expect(Thumbnailer.pixelSize(of: Data("not an image".utf8)) == nil, "not an image")
    }
    T.test("images store their pixel size at insert; other kinds have none") {
        let dir = tmp(); let s = try ClipStore(directory: dir)
        let img = try s.insert(imageContent(width: 30, height: 20), sourceBundleID: nil, sourceAppName: nil)
        T.equal(img.pixelSize, PixelSize(width: 30, height: 20))
        T.equal(try s.insert(text("hi"), sourceBundleID: nil, sourceAppName: nil).pixelSize, nil)
        T.equal(try ClipStore(directory: dir).recent(filter: .images, limit: 5, offset: 0).first?.pixelSize,
                PixelSize(width: 30, height: 20), "after reopening")
    }
    T.test("a version 1 database gains pixel sizes on open, and survives an older build in between") {
        let dir = tmp()
        let blobs = dir.appendingPathComponent("blobs"); let thumbs = dir.appendingPathComponent("thumbs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try imageData(width: 64, height: 48).write(to: blobs.appendingPathComponent("b1"))
        let path = dir.appendingPathComponent("clipt.sqlite").path
        func sql(_ statements: String) {
            var db: OpaquePointer?
            sqlite3_open(path, &db)
            T.equal(sqlite3_exec(db, statements, nil, nil, nil), SQLITE_OK, "setup sql")
            sqlite3_close(db)
        }
        // The version 1 schema, as shipped, with one image and one image whose blob is gone.
        sql("""
            CREATE TABLE items(id INTEGER PRIMARY KEY, hash TEXT UNIQUE, kind TEXT, preview TEXT, plain_text TEXT,
                source_bundle TEXT, source_name TEXT, copied_at REAL, pinned_at REAL NULL, byte_size INTEGER, thumb TEXT NULL);
            CREATE TABLE reps(item_id INTEGER, ord INTEGER, type TEXT, blob TEXT, size INTEGER);
            CREATE VIRTUAL TABLE fts USING fts5(plain_text, ocr_text, tokenize='unicode61 remove_diacritics 2');
            INSERT INTO items VALUES(1, 'h1', 'image', 'Image', NULL, NULL, NULL, 10, NULL, 100, NULL);
            INSERT INTO reps VALUES(1, 0, 'public.png', 'b1', 100);
            INSERT INTO items VALUES(2, 'h2', 'image', 'Image', NULL, NULL, NULL, 5, NULL, 100, NULL);
            INSERT INTO reps VALUES(2, 0, 'public.png', 'missing', 100);
            PRAGMA user_version = 1;
            """)
        let s = try ClipStore(directory: dir)
        let rows = try s.recent(filter: .all, limit: 5, offset: 0)
        T.equal(rows.map(\.pixelSize), [PixelSize(width: 64, height: 48), nil])
        T.equal(try s.recent(filter: .all, limit: 5, offset: 0).map(\.preview), ["Image", "Image"], "rows kept")
        // An older build opening it writes version 1 again; the columns stay and the next open must cope.
        sql("PRAGMA user_version = 1;")
        let again = try ClipStore(directory: dir)
        T.equal(try again.recent(filter: .all, limit: 5, offset: 0).first?.pixelSize, PixelSize(width: 64, height: 48))
        var db: OpaquePointer?; sqlite3_open(path, &db)
        var st: OpaquePointer?; sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &st, nil); sqlite3_step(st)
        T.equal(sqlite3_column_int(st, 0), 2, "user_version")
        sqlite3_finalize(st); sqlite3_close(db)
    }
    T.test("re-copy with a different secondary representation adds no blobs") {
        let dir = tmp(); let s = try ClipStore(directory: dir)
        let blobs = dir.appendingPathComponent("blobs").path
        func rich(_ rtf: String) -> ClipContent {
            ClipClassifier.content(from: snap([("public.utf8-plain-text", "same"), ("public.rtf", rtf)]))!
        }
        try s.insert(rich("{\\rtf1 one}"), sourceBundleID: nil, sourceAppName: nil)
        let before = try FileManager.default.contentsOfDirectory(atPath: blobs).count
        try s.insert(rich("{\\rtf1 two}"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(try FileManager.default.contentsOfDirectory(atPath: blobs).count, before); T.equal(try s.count(), 1)
    }
    T.test("opening the store sweeps orphan blobs and keeps referenced ones") {
        let dir = tmp(); var s: ClipStore? = try ClipStore(directory: dir)
        let i = try s!.insert(text("keep me"), sourceBundleID: nil, sourceAppName: nil)
        let orphan = dir.appendingPathComponent("blobs/deadbeef")
        try Data("x".utf8).write(to: orphan)
        s = nil
        let s2 = try ClipStore(directory: dir)
        T.expect(!FileManager.default.fileExists(atPath: orphan.path), "orphan removed")
        T.equal(try s2.representations(of: i.id).first?.data, Data("keep me".utf8))
    }
    T.test("performance: 10k items, a 5 MB item, search under 50 ms") {
        let s = try ClipStore(directory: tmp())
        try s.batch { for i in 0..<10_000 { try s.insert(text("item \(i) lorem ipsum dolor \(i * 7)"), sourceBundleID: nil, sourceAppName: nil) } }
        let big = text(String(repeating: "log line\n", count: 550_000))
        let start = Date(); try s.insert(big, sourceBundleID: nil, sourceAppName: nil)
        let t1 = Date().timeIntervalSince(start); print("    5 MB insert: \(Int(t1 * 1000)) ms")
        T.lessThan(t1, 0.2, "5 MB insert")
        let q = Date(); _ = try s.search("ipsum 4242", filter: .all, limit: 50)
        let t2 = Date().timeIntervalSince(q); print("    search: \(Int(t2 * 1000)) ms")
        T.lessThan(t2, 0.05, "search")
        let r = Date(); _ = try s.recent(filter: .all, limit: 50, offset: 0)
        let t3 = Date().timeIntervalSince(r); print("    first page: \(String(format: "%.2f", t3 * 1000)) ms")
        T.lessThan(t3, 0.01, "first page")
    }
}
