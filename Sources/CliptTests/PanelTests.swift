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
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900), right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let f = PanelPlacement.frame(screens: [main, right], mouse: CGPoint(x: 2000, y: 500))
        T.equal(f.midX, right.midX); T.equal(f.maxY, right.maxY - right.height * 0.22)
        T.equal(f.size, PanelPlacement.size)
        T.equal(PanelPlacement.frame(screens: [main], mouse: CGPoint(x: -500, y: -500)).midX, main.midX)
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
    T.test("type line") {
        T.equal(PanelFormat.typeLine(kind: .link, characters: 36, byteSize: 36), "Link · 36 characters")
        T.equal(PanelFormat.typeLine(kind: .text, characters: 1, byteSize: 1), "Text · 1 character")
        T.equal(PanelFormat.typeLine(kind: .text, characters: 1204, byteSize: 1204, locale: Locale(identifier: "en_US")), "Text · 1,204 characters")
        T.equal(PanelFormat.typeLine(kind: .text, characters: nil, byteSize: 9), "Text")
        T.equal(PanelFormat.typeLine(kind: .file, characters: nil, byteSize: 9, fileCount: 3), "Files · 3 items")
        T.equal(PanelFormat.typeLine(kind: .file, characters: nil, byteSize: 9, fileCount: 1), "File")
        T.expect(PanelFormat.typeLine(kind: .image, characters: nil, byteSize: 1_200_000).hasPrefix("Image · "), "image size")
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
    T.test("keys: typing and ⌫ while searching belong to the search field") {
        T.equal(PanelCommand.resolve(.character("p"), command: false, option: false, queryIsEmpty: true), nil)
        T.equal(PanelCommand.resolve(.character("3"), command: false, option: false, queryIsEmpty: true), nil)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: false, queryIsEmpty: false), nil)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: false, queryIsEmpty: true), .delete)
        T.equal(PanelCommand.resolve(.backspace, command: false, option: true, queryIsEmpty: true), nil)
    }
}
