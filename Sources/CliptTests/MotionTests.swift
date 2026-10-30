import Foundation
import CliptCore

func motionTests() {
    print("Motion")
    T.test("Reduce Motion or motion off means fades only") {
        T.equal(MotionStyle(reduceMotion: false, motionEnabled: true), .springs)
        T.equal(MotionStyle(reduceMotion: true, motionEnabled: true), .fades)
        T.equal(MotionStyle(reduceMotion: false, motionEnabled: false), .fades)
        T.equal(MotionStyle(reduceMotion: true, motionEnabled: false), .fades)
    }
    T.test("fades never scale, pulse or move") {
        let f = MotionStyle.fades
        T.equal(f.moves, false); T.equal(f.pulsesOnPaste, false)
        T.equal(f.openScale, 1); T.equal(f.closeScale, 1)
        T.equal(f.openFadeDuration, 0.12); T.equal(f.closeDuration, 0.12)
    }
    T.test("springs open from 0.96 and close to 0.98") {
        let s = MotionStyle.springs
        T.equal(s.openScale, 0.96); T.equal(s.closeScale, 0.98); T.equal(s.moves, true)
        T.lessThan(s.closeDuration, s.openFadeDuration + 0.001, "close is quicker than open")
    }
    T.test("list changes do not animate while the panel builds up") {
        T.equal(PanelMotion.animatesListChanges(style: .springs, visible: true, initialLoadLanded: false, secondsSinceShow: 5), false)
        T.equal(PanelMotion.animatesListChanges(style: .springs, visible: true, initialLoadLanded: true, secondsSinceShow: 0.05), false)
        T.equal(PanelMotion.animatesListChanges(style: .springs, visible: false, initialLoadLanded: true, secondsSinceShow: 5), false)
        T.equal(PanelMotion.animatesListChanges(style: .springs, visible: true, initialLoadLanded: true, secondsSinceShow: 0.3), true)
    }
    T.test("fades-only mode never animates list changes (that would slide rows)") {
        T.equal(PanelMotion.animatesListChanges(style: .fades, visible: true, initialLoadLanded: true, secondsSinceShow: 5), false)
        T.equal(PanelMotion.isSettledOpen(visible: true, initialLoadLanded: true, secondsSinceShow: 5), true)
    }
    T.test("no paste while the panel is closing or already pasting") {
        T.equal(PanelMotion.allowsPaste(isClosing: false, isPasting: false), true)
        T.equal(PanelMotion.allowsPaste(isClosing: true, isPasting: false), false)
        T.equal(PanelMotion.allowsPaste(isClosing: false, isPasting: true), false)
    }
    T.test("paste starts well inside the 250 ms budget") {
        T.lessThan(PanelMotion.pasteStartDelay(style: .springs), 0.18, "springs")
        T.lessThan(PanelMotion.pasteStartDelay(style: .fades), 0.13, "fades")
        T.lessThan(PanelMotion.pasteCloseDuration, PanelMotion.pasteHandoff + 0.001, "close ends by the handoff")
    }
    T.test("a held arrow key never animates the scroll") {
        T.equal(PanelMotion.animatesScroll(isKeyRepeat: true, style: .springs), false)
        T.equal(PanelMotion.animatesScroll(isKeyRepeat: false, style: .springs), true)
        T.equal(PanelMotion.animatesScroll(isKeyRepeat: false, style: .fades), false)
    }
    T.test("ease curves run 0 to 1 and never step backwards") {
        for e in [Ease.settle, Ease.exit] {
            T.equal(e(0), 0); T.equal(e(1), 1); T.equal(e(-1), 0); T.equal(e(2), 1)
            var last = 0.0, monotonic = true
            for i in 1...100 { let v = e(Double(i) / 100); if v < last - 1e-9 { monotonic = false }; last = v }
            T.expect(monotonic, "monotonic")
        }
        T.lessThan(abs(Ease(0, 0, 1, 1)(0.5) - 0.5), 1e-6, "symmetric curve is 0.5 at its middle")
        T.lessThan(0.75, Ease.settle(0.3), "settle is mostly there early")
        T.lessThan(Ease.exit(0.3), 0.2, "exit starts slowly")
    }
}
