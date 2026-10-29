import Foundation
import CliptCore

func pasteTests() {
    print("Paste")
    T.test("routes") {
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: true, ownPID: 1), .synthesizeCommandV)
        T.equal(PastePlan.route(hasAccessibility: false, targetPID: 500, targetIsRunning: true, ownPID: 1), .copyOnly(.noAccessibility))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: nil, targetIsRunning: false, ownPID: 1), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 500, targetIsRunning: false, ownPID: 1), .copyOnly(.noTargetApp))
        T.equal(PastePlan.route(hasAccessibility: true, targetPID: 1, targetIsRunning: true, ownPID: 1), .copyOnly(.noTargetApp))
    }
    T.test("plain text keeps only the plain text representation") {
        let reps = [Representation(type: PasteType.plainText, data: Data("x".utf8)), Representation(type: PasteType.rtf, data: Data("{}".utf8))]
        T.equal(PastePlan.representations(reps, plainText: true).map(\.type), [PasteType.plainText])
        T.equal(PastePlan.representations(reps, plainText: false), reps)
        let img = [Representation(type: PasteType.png, data: Data([1]))]
        T.equal(PastePlan.representations(img, plainText: true), img)
    }
}
