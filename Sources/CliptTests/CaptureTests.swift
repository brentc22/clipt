import Foundation
import CliptCore

func captureTests() {
    print("Capture")
    T.test("user pause wins over access") {
        T.equal(CaptureGate.state(userPaused: true, accessAllowed: false), .pausedByUser)
        T.equal(CaptureGate.state(userPaused: false, accessAllowed: false), .noPasteboardAccess)
        T.equal(CaptureGate.state(userPaused: false, accessAllowed: true), .active)
    }
    T.test("own writes are claimed once") {
        var t = OwnWriteTracker(); t.recordWrite(changeCount: 41, itemID: 7)
        T.equal(t.claim(changeCount: 40), nil); T.equal(t.claim(changeCount: 41), 7); T.equal(t.claim(changeCount: 41), nil)
    }
}
