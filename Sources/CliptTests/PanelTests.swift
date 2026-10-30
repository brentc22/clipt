import Foundation
import CliptCore

private func item(_ id: Int64, pinned: Bool = false) -> ClipItem {
    ClipItem(id: id, kind: .text, preview: "item \(id)", sourceBundleID: nil, sourceAppName: nil,
             copiedAt: Date(timeIntervalSince1970: Double(id)), isPinned: pinned, byteSize: 1, thumbnailURL: nil)
}

func panelTests() {
    print("Panel")
    T.test("opens on the newest recent item") {
        T.equal(PanelList(pinned: [item(1, pinned: true)], recent: [item(2), item(3)]).selection, 2)
        T.equal(PanelList(pinned: [item(1, pinned: true)], recent: []).selection, 1)
    }
    T.test("selection clamps") {
        var l = PanelList(pinned: [], recent: [item(1), item(2)]); l.moveSelection(by: 5); T.equal(l.selection, 2)
        l.moveSelection(by: -9); T.equal(l.selection, 1)
    }
    T.test("⌘N hints follow visible recent rows, never pins") {
        let l = PanelList(pinned: [item(99, pinned: true)], recent: (1...12).map { item(Int64($0)) })
        T.equal(l.hotkeyNumber(for: 99), nil); T.equal(l.hotkeyNumber(for: 1), 1); T.equal(l.hotkeyNumber(for: 10), nil)
        T.equal(l.item(forHotkey: 3)?.id, 3)
    }
    T.test("after filtering, ⌘N pastes exactly the row that shows it") {
        var l = PanelList(pinned: [], recent: (1...5).map { item(Int64($0)) })
        l.replace(pinned: [], recent: [item(4), item(2)], resetSelection: true)
        T.equal(l.item(forHotkey: 1)?.id, 4); T.equal(l.hotkeyNumber(for: 2), 2); T.equal(l.selection, 4)
    }
    T.test("replace keeps a still-present selection, else falls back") {
        var l = PanelList(pinned: [], recent: [item(1), item(2), item(3)])
        l.select(2)
        l.replace(pinned: [], recent: [item(3), item(2)], resetSelection: false); T.equal(l.selection, 2)
        l.replace(pinned: [], recent: [item(5)], resetSelection: false); T.equal(l.selection, 5)
        l.replace(pinned: [], recent: [], resetSelection: false); T.equal(l.selection, nil)
    }
    T.test("selection moves across pinned then recent; select ignores unknown ids") {
        var l = PanelList(pinned: [item(9, pinned: true)], recent: [item(1), item(2)])
        l.moveSelection(by: -1); T.equal(l.selection, 9)
        l.moveSelection(by: 2); T.equal(l.selection, 2)
        l.select(77); T.equal(l.selection, 2)
        T.equal(PanelList(pinned: [], recent: []).selection, nil)
    }
    T.test("appendPage extends recent and drives needsNextPage") {
        var l = PanelList(pinned: [], recent: (1...50).map { item(Int64($0)) })
        T.expect(!l.needsNextPage, "top of a list needs no page")
        l.select(45); T.expect(l.needsNextPage, "within 10 of the end")
        l.appendPage((51...100).map { item(Int64($0)) })
        T.equal(l.recent.count, 100); T.expect(!l.needsNextPage, "more rows below now")
    }
    T.test("appendPage drops ids already shown") {
        var l = PanelList(pinned: [item(99, pinned: true)], recent: (1...50).map { item(Int64($0)) })
        l.appendPage([item(50), item(99), item(51)])
        T.equal(l.recent.map(\.id).count, 51); T.equal(Set(l.rows.map(\.id)).count, l.rows.count)
        T.equal(l.recent.last?.id, 51)
    }
    T.test("short or empty lists are exhausted and never ask for more") {
        T.expect(!PanelList(pinned: [], recent: []).needsNextPage, "empty")
        T.expect(!PanelList(pinned: [], recent: [item(1)]).needsNextPage, "short")
        var l = PanelList(pinned: [], recent: (1...50).map { item(Int64($0)) })
        T.expect(!l.isExhausted, "full page")
        l.appendPage((51...60).map { item(Int64($0)) })
        T.expect(l.isExhausted, "short page exhausts"); l.select(60); T.expect(!l.needsNextPage, "no more")
        l.replace(pinned: [], recent: (1...50).map { item(Int64($0)) }, resetSelection: true)
        T.expect(!l.isExhausted, "replace re-derives")
    }
    T.test("placement: screen under the mouse, centered, upper part") {
        let mainFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let main = PanelPlacement.Screen(frame: mainFrame, visible: CGRect(x: 0, y: 70, width: 1440, height: 800))
        let rightFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let right = PanelPlacement.Screen(frame: rightFrame, visible: CGRect(x: 1440, y: 0, width: 1920, height: 1050))
        let f = PanelPlacement.frame(screens: [main, right], mouse: CGPoint(x: 2000, y: 500))
        T.equal(f.midX, right.visible.midX); T.equal(f.maxY, right.visible.maxY - right.visible.height * 0.22)
        T.equal(f.size, PanelPlacement.size)
        T.equal(PanelPlacement.size, CGSize(width: 540, height: 330), "compact panel")
        T.equal(PanelPlacement.frame(screens: [main], mouse: CGPoint(x: -500, y: -500)).midX, main.visible.midX)
    }
    T.test("placement: the mouse in a second display's menu bar or Dock picks that display") {
        let main = PanelPlacement.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         visible: CGRect(x: 0, y: 70, width: 1440, height: 800))
        let right = PanelPlacement.Screen(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                          visible: CGRect(x: 1440, y: 0, width: 1920, height: 1050))
        let menuBar = PanelPlacement.frame(screens: [main, right], mouse: CGPoint(x: 2000, y: 1070))
        T.equal(menuBar.midX, right.visible.midX)
        T.expect(right.visible.contains(menuBar), "inside the visible frame")
        let dock = PanelPlacement.frame(screens: [main, right], mouse: CGPoint(x: 700, y: 20))
        T.equal(dock.midX, main.visible.midX)
        T.expect(main.visible.contains(dock), "inside the visible frame")
    }
    T.test("hidden panel: no preview and no paging on a background reload") {
        T.equal(PanelWork.loadsPreview(visible: false, selection: 4, loadedID: nil), false)
        T.equal(PanelWork.loadsPreview(visible: true, selection: 4, loadedID: nil), true)
        T.equal(PanelWork.loadsPreview(visible: true, selection: 4, loadedID: 4), false)
        T.equal(PanelWork.pagesIn(visible: false, needsNextPage: true), false)
        T.equal(PanelWork.pagesIn(visible: true, needsNextPage: true), true)
    }
    T.test("remove selects the row that took its place, else the one above") {
        var l = PanelList(pinned: [item(9, pinned: true)], recent: [item(1), item(2), item(3)])
        l.select(2); l.remove(2); T.equal(l.selection, 3); T.equal(l.rows.map(\.id), [9, 1, 3])
        l.remove(3); T.equal(l.selection, 1)
        l.remove(9); T.equal(l.selection, 1); T.equal(l.pinned.count, 0)
        l.remove(1); T.equal(l.selection, nil)
        var full = PanelList(pinned: [], recent: (1...50).map { item(Int64($0)) })
        full.remove(5); T.expect(!full.isExhausted, "a local delete keeps paging alive")
        full.markExhausted(); full.select(49); T.expect(!full.needsNextPage, "exhausted lists never page")
    }

    print("Panel text and keys")
    T.test("relative times") {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        T.equal(PanelFormat.relative(now, now: now), "just now")
        T.equal(PanelFormat.relative(now.addingTimeInterval(-59), now: now), "just now")
        T.equal(PanelFormat.relative(now.addingTimeInterval(-120), now: now), "2 min ago")
        T.equal(PanelFormat.relative(now.addingTimeInterval(-3 * 3600), now: now), "3 hr ago")
        T.equal(PanelFormat.relative(now.addingTimeInterval(30), now: now), "just now", "clock skew")
        T.equal(PanelFormat.relative(now.addingTimeInterval(-4 * 86400), now: now), "4 days ago")
    }
    T.test("image dimensions use a real multiplication sign") {
        let d = PanelFormat.dimensions(PixelSize(width: 3024, height: 1964))
        T.equal(d, "3024 \u{00D7} 1964")
        T.equal(Array(d.unicodeScalars).map(\.value)[4...6].map { $0 }, [0x20, 0xD7, 0x20], "space, ×, space")
        T.equal(PanelFormat.dimensions(PixelSize(width: 12000, height: 8)), "12000 × 8", "no grouping")
    }
    T.test("image rows show the pixel size instead of \"Image\"") {
        T.equal(PanelFormat.rowText(kind: .image, preview: "Image", pixelSize: PixelSize(width: 1360, height: 888)), "1360 × 888")
        T.equal(PanelFormat.rowText(kind: .image, preview: "Image", pixelSize: nil), "Image", "unknown size")
        T.equal(PanelFormat.rowText(kind: .text, preview: "hello", pixelSize: PixelSize(width: 1, height: 1)), "hello")
    }
    T.test("one-line meta") {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func line(_ kind: ClipKind, chars: Int? = nil, bytes: Int = 9, files: Int? = nil, px: PixelSize? = nil,
                  ago: TimeInterval = 5) -> String {
            PanelFormat.metaLine(source: "Safari", copiedAt: now.addingTimeInterval(-ago), kind: kind, characters: chars,
                                 byteSize: bytes, fileCount: files, pixelSize: px, now: now)
        }
        T.equal(line(.image, bytes: 2_400_000, px: PixelSize(width: 3024, height: 1964)), "Safari · just now · 3024 × 1964 · 2.4 MB")
        T.equal(line(.image, bytes: 1_800_000), "Safari · just now · 1.8 MB", "size unknown")
        T.equal(line(.link, chars: 36, ago: 120), "Safari · 2 min ago · 36 characters")
        T.equal(line(.text, chars: 1), "Safari · just now · 1 character")
        T.equal(line(.text, chars: 1204), "Safari · just now · 1,204 characters")
        T.equal(line(.text), "Safari · just now", "still loading")
        T.equal(line(.color), "Safari · just now")
        T.equal(line(.file, files: 3), "Safari · just now · 3 items")
        T.equal(line(.file, files: 1), "Safari · just now · 1 item")
    }
    T.test("UI numbers and dates stay English under a Dutch locale") {
        // This Mac runs nl_BE (it printed "1.204" and "1,8 MB" before the fix); pin a
        // Dutch calendar too so the test means the same on any machine.
        var nl = Calendar(identifier: .gregorian)
        nl.locale = Locale(identifier: "nl_BE")
        nl.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // 15 Jan 2027
        T.equal(PanelFormat.metaLine(source: "Mail", copiedAt: now, kind: .image, characters: nil, byteSize: 1_800_000,
                                     pixelSize: PixelSize(width: 3024, height: 1964), now: now, calendar: nl),
                "Mail · just now · 3024 × 1964 · 1.8 MB")
        T.equal(PanelFormat.metaLine(source: "Mail", copiedAt: now, kind: .text, characters: 1204, byteSize: 1,
                                     now: now, calendar: nl), "Mail · just now · 1,204 characters")
        let old = now.addingTimeInterval(-10 * 86400)           // 5 Jan 2027
        T.equal(PanelFormat.relative(old, now: now, calendar: nl), "Jan 5")
        T.equal(PanelFormat.relative(old.addingTimeInterval(-400 * 86400), now: now, calendar: nl), "Dec 1, 2025")
    }
    T.test("hex colors") {
        let c = PanelFormat.hexColor("#FF375F")
        T.equal(c?.red, 1); T.equal(c?.alpha, 1); T.equal(c.map { Int(($0.green * 255).rounded()) }, 0x37)
        T.equal(PanelFormat.hexColor("00000080")?.alpha, Double(0x80) / 255)
        T.expect(PanelFormat.hexColor("#XYZ123") == nil, "not hex"); T.expect(PanelFormat.hexColor("#FFF") == nil, "short form")
    }
    T.test("keys: arrows, return, hotkeys, pin, escape") {
        func r(_ k: PanelKey, cmd: Bool = false, opt: Bool = false, empty: Bool = true) -> PanelCommand? {
            PanelCommand.resolve(k, command: cmd, option: opt, queryIsEmpty: empty)
        }
        T.equal(r(.up), .move(-1)); T.equal(r(.down, empty: false), .move(1))
        T.equal(r(.enter), .paste(plainText: false)); T.equal(r(.enter, opt: true), .paste(plainText: true))
        T.equal(r(.character("3"), cmd: true), .pasteHotkey(3)); T.equal(r(.character("0"), cmd: true), nil)
        T.equal(r(.character("p"), cmd: true), .togglePin); T.equal(r(.escape, empty: false), .escape)
    }
    T.test("keys: ⌘1–⌘9 follow the physical number row (AZERTY)") {
        func r(_ c: Character, _ code: UInt16) -> PanelCommand? {
            PanelCommand.resolve(.character(c), command: true, option: false, queryIsEmpty: true, keyCode: code)
        }
        // kVK_ANSI_1…9 = 18 19 20 21 23 22 26 28 25; AZERTY types & é " ' ( § è ! ç there.
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let azerty: [Character] = ["&", "é", "\"", "'", "(", "§", "è", "!", "ç"]
        for (i, code) in codes.enumerated() { T.equal(r(azerty[i], code), .pasteHotkey(i + 1), "key \(code)") }
        T.equal(r("0", 29), nil, "⌘0 is not a hotkey")
        T.equal(r("1", 83), nil, "keypad 1 is not the number row")
        T.equal(r("p", 35), .togglePin, "⌘P by character")
        T.equal(PanelCommand.resolve(.character("&"), command: true, option: false, queryIsEmpty: true), nil)
    }
    T.test("keys: auto-repeat only moves") {
        func r(_ k: PanelKey, cmd: Bool = false, empty: Bool = true, code: UInt16? = nil) -> PanelCommand? {
            PanelCommand.resolve(k, command: cmd, option: false, queryIsEmpty: empty, keyCode: code, isRepeat: true)
        }
        T.equal(r(.down), .move(1)); T.equal(r(.up), .move(-1))
        T.equal(r(.backspace), nil, "held ⌫ must not delete history once the field is empty")
        T.equal(r(.enter), nil, "held ↩ must not paste twice")
        T.equal(r(.character("&"), cmd: true, code: 18), nil, "held ⌘1 must not paste twice")
        T.equal(r(.character("p"), cmd: true), nil); T.equal(r(.escape), nil)
    }
    T.test("keys: typing and ⌫ while searching belong to the search field") {
        T.equal(PanelCommand.resolve(.character("p"), command: false, option: false, queryIsEmpty: true), nil)
        T.equal(PanelCommand.resolve(.character("3"), command: false, option: false, queryIsEmpty: true), nil)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: false, queryIsEmpty: false), nil)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: false, queryIsEmpty: true), .delete)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: true, queryIsEmpty: true), nil)
    }
}
