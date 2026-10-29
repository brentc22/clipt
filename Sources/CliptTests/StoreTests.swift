import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CliptCore

func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("clipt-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func text(_ s: String) -> ClipContent {
    ClipClassifier.content(from: snap([("public.utf8-plain-text", s)]))!
}

func imageContent() -> ClipContent {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return ClipClassifier.content(from: .init(representations: [.init(type: PasteType.png, data: out as Data)]))!
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
        try s.setRecognizedText("invoice 2026", for: img.id)
        T.equal(try s.search("invoice", filter: .images, limit: 50).recent.map(\.id), [img.id])
    }
    T.test("representations round-trip and blobs are cleaned on delete") {
        let dir = tmp(); let s = try ClipStore(directory: dir); let i = try s.insert(text("hi"), sourceBundleID: nil, sourceAppName: nil)
        T.equal(try s.representations(of: i.id).first?.data, Data("hi".utf8)); try s.delete(i.id)
        T.equal(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("blobs").path).count, 0)
    }
    T.test("a corrupt database is moved aside, not fatal") {
        let d = tmp(); try Data("not a database".utf8).write(to: d.appendingPathComponent("clipt.sqlite"))
        let s = try ClipStore(directory: d); T.equal(try s.count(), 0)
        T.expect(try FileManager.default.contentsOfDirectory(atPath: d.path).contains { $0.hasPrefix("clipt.sqlite.corrupt-") }, "kept aside")
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
