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
        T.equal(PanelMotion.animatesListChanges(visible: true, initialLoadLanded: false, secondsSinceShow: 5), false)
        T.equal(PanelMotion.animatesListChanges(visible: true, initialLoadLanded: true, secondsSinceShow: 0.05), false)
        T.equal(PanelMotion.animatesListChanges(visible: false, initialLoadLanded: true, secondsSinceShow: 5), false)
        T.equal(PanelMotion.animatesListChanges(visible: true, initialLoadLanded: true, secondsSinceShow: 0.3), true)
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
}
