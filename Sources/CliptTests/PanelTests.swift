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
}
