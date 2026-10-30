import Foundation
import CliptCore

func pasteTests() {
    print("Paste")
    T.test("routes") {
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: nil, kind: .text), .synthesizeCommandV)
        T.equal(PastePlan.route(hasAccessibility: false, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: nil, kind: .text), .copyOnly(.noAccessibility))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: nil, targetIsRunning: false, ownPID: 1, targetBundleID: nil, kind: .text), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: false, ownPID: 1, targetBundleID: nil, kind: .text), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 1, targetIsRunning: true, ownPID: 1, targetBundleID: nil, kind: .text), .copyOnly(.noTargetApp))
    }
    T.test("Finder takes only files") {
        let finder = PastePlan.finderBundleID
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: finder, kind: .text), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: finder, kind: .image), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: finder, kind: .file), .synthesizeCommandV)
        T.equal(PastePlan.route(hasAccessibility: false, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: finder, kind: .file), .copyOnly(.noAccessibility))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1, targetBundleID: "com.apple.TextEdit", kind: .text), .synthesizeCommandV)
    }
    T.test("plain text keeps only the plain text representation") {
        let reps = [Representation(type: PasteType.plainText, data: Data("x".utf8)), Representation(type: PasteType.rtf, data: Data("{}".utf8))]
        T.equal(PastePlan.representations(reps, plainText: true).map(\.type), [PasteType.plainText])
        T.equal(PastePlan.representations(reps, plainText: false), reps)
        let img = [Representation(type: PasteType.png, data: Data([1]))]
        T.equal(PastePlan.representations(img, plainText: true), img)
    }
    T.test("several files become one pasteboard item each") {
        let u = (1...3).map { Representation(type: PasteType.fileURL, data: Data("file:///tmp/\($0)".utf8)) }
        let text = Representation(type: PasteType.plainText, data: Data("1\n2\n3".utf8))
        let items = PastePlan.pasteboardItems([u[0], text, u[1], u[2]])
        T.equal(items.count, 3)
        T.equal(items[0], [u[0], text])
        T.equal(items[1], [u[1]])
        T.equal(items[2], [u[2]])
        T.equal(PastePlan.pasteboardItems([text]), [[text]])
        T.equal(PastePlan.pasteboardItems([]).count, 0)
    }
    T.test("plain-text paste of a file routes as text") {
        let u = Representation(type: PasteType.fileURL, data: Data("file:///tmp/a".utf8))
        let text = Representation(type: PasteType.plainText, data: Data("a".utf8))
        T.equal(PastePlan.pasteKind(.file, writing: [u, text]), .file)
        T.equal(PastePlan.pasteKind(.file, writing: [text]), .text)
        T.equal(PastePlan.pasteKind(.image, writing: [text]), .image)
    }
}
