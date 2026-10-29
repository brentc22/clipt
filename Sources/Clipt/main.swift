import AppKit

let app = NSApplication.shared
// Accessory: no Dock icon; a menu bar item and a global hotkey instead.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
