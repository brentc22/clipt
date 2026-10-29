import Foundation
@testable import CliptCore

func snap(_ reps: [(String, String)]) -> PasteboardSnapshot { .init(representations: reps.map { .init(type: $0.0, data: Data($0.1.utf8)) }) }

func classifierTests() {
    print("Classifier")
    T.test("concealed and transient types are skipped") {
        T.expect(CaptureFilter.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundleID: nil, ignoredApps: []), "concealed")
        T.expect(CaptureFilter.shouldSkip(types: ["com.agilebits.onepassword"], sourceBundleID: nil, ignoredApps: []), "1Password marker")
        T.expect(!CaptureFilter.shouldSkip(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari", ignoredApps: []), "normal text")
    }
    T.test("ignored apps are skipped") {
        T.expect(CaptureFilter.shouldSkip(types: ["public.utf8-plain-text"], sourceBundleID: "com.bitwarden.desktop", ignoredApps: Set(CaptureFilter.defaultIgnoredApps)), "bitwarden")
    }
    T.test("text, link and color kinds") {
        T.equal(ClipClassifier.content(from: snap([("public.utf8-plain-text", "hello")]))?.kind, .text)
        T.equal(ClipClassifier.content(from: snap([("public.utf8-plain-text", "https://github.com/brentc22/clipt")]))?.kind, .link)
        T.equal(ClipClassifier.content(from: snap([("public.utf8-plain-text", "#FF375F")]))?.kind, .color)
    }
    T.test("preview is one collapsed line of at most 300 characters") {
        let c = ClipClassifier.content(from: snap([("public.utf8-plain-text", "  a\n\n  b\t c " + String(repeating: "x", count: 1000))]))!
        T.expect(c.preview.hasPrefix("a b c "), "collapsed whitespace"); T.expect(c.preview.count <= 300, "capped")
    }
    T.test("same text with different rich types hashes the same") {
        let a = ClipClassifier.content(from: snap([("public.utf8-plain-text", "same"), ("public.rtf", "{\\rtf1 same}")]))!
        let b = ClipClassifier.content(from: snap([("public.utf8-plain-text", "same")]))!
        T.equal(a.primaryHash, b.primaryHash)
    }
    T.test("empty or whitespace-only pasteboards are ignored") {
        T.equal(ClipClassifier.content(from: .init(representations: [])), nil)
        T.equal(ClipClassifier.content(from: snap([("public.utf8-plain-text", "  \n ")])), nil)
        T.equal(ClipClassifier.content(from: snap([("com.apple.NSFilePromiseItemMetaData", "")])), nil)
    }
    T.test("over the size cap only understood types are kept") {
        let big = Representation(type: "com.microsoft.Excel.sheet", data: Data(count: 21_000_000))
        let c = ClipClassifier.content(from: .init(representations: [.init(type: PasteType.plainText, data: Data("A1".utf8)), big]))!
        T.equal(c.representations.map(\.type), [PasteType.plainText])
    }
    T.test("an image is an image, a file URL is a file") {
        let png = Representation(type: PasteType.png, data: Data([0x89, 0x50, 0x4E, 0x47]))
        T.equal(ClipClassifier.content(from: .init(representations: [png]))?.kind, .image)
        T.equal(ClipClassifier.content(from: snap([(PasteType.fileURL, "file:///Users/x/a.pdf")]))?.kind, .file)
    }
}
