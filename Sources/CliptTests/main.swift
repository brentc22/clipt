import Foundation
import CliptCore

// Line-buffer stdout so CI logs show which test was running if one hangs.
setvbuf(stdout, nil, _IOLBF, 0)

print("Version")
T.test("version falls back outside a bundle") { T.equal(CliptVersion.current, "0.0.0") }
classifierTests()
storeTests()
captureTests()
pasteTests()
panelTests()
motionTests()
T.finish()
