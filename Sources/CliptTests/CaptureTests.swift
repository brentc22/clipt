import Foundation
import CliptCore

func captureTests() {
    print("Capture")
    T.test("user pause wins over access") {
        T.equal(CaptureGate.state(userPaused: true, accessAllowed: false), .pausedByUser)
        T.equal(CaptureGate.state(userPaused: false, accessAllowed: false), .noPasteboardAccess)
        T.equal(CaptureGate.state(userPaused: false, accessAllowed: true), .active)
    }
    T.test("pasteboard access: capture runs until denied, green only for Allow") {
        T.equal(PasteboardAccess.capturesAllowed(.alwaysAllow), true)
        T.equal(PasteboardAccess.capturesAllowed(.notDecided), true)
        T.equal(PasteboardAccess.capturesAllowed(.ask), false)
        T.equal(PasteboardAccess.capturesAllowed(.alwaysDeny), false)
        T.equal(PasteboardAccess.capturesAllowed(.unknown), false)
        T.equal(PasteboardAccess.status(.alwaysAllow), .allowed)
        T.equal(PasteboardAccess.status(.notDecided), .notDecided)
        T.equal(PasteboardAccess.status(.ask), .denied)
        T.equal(PasteboardAccess.status(.alwaysDeny), .denied)
        T.equal(PasteboardAccess.status(.unknown), .denied)
    }
    T.test("own writes are claimed once") {
        var t = OwnWriteTracker(); t.recordWrite(changeCount: 41, itemID: 7)
        T.equal(t.claim(changeCount: 40), nil); T.equal(t.claim(changeCount: 41), 7); T.equal(t.claim(changeCount: 41), nil)
    }
}
