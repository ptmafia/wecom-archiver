import AppKit
import ApplicationServices
import Foundation
import WeComCore

struct ConvRow {
    let name: String
    let preview: String
    let badge: Bool
    let muted: Bool
    let element: AXUIElement
    var facts: RowFacts { RowFacts(name: name, preview: preview, badge: badge, muted: muted) }
}

enum SelectResult { case ok, noRow, noPane, interrupted, held }

/// Everything that talks to WeCom through the Accessibility API.
final class Driver {
    /// Every WeCom process. Documents and sheets open in their own windows, sometimes in another process.
    private let apps: [AXUIElement]
    /// Asked with the row as it is right now, just before opening it. A pass runs for hours and the list goes stale.
    var mayOpen: (RowFacts) -> Bool = { _ in false }

    init?() {
        apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.WeWorkMac")
            .map { AXUIElementCreateApplication($0.processIdentifier) }
        if apps.isEmpty { return nil }
    }

    private func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
    }
    private func str(_ e: AXUIElement, _ n: String) -> String { attr(e, n) as? String ?? "" }
    private func kids(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func role(_ e: AXUIElement) -> String { str(e, kAXRoleAttribute) }
    private func frame(_ e: AXUIElement) -> CGRect {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return .zero }
        var o = CGPoint.zero, z = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &o)
        AXValueGetValue(s as! AXValue, .cgSize, &z)
        return CGRect(origin: o, size: z)
    }
    private func setBool(_ e: AXUIElement, _ n: String) -> Bool {
        AXUIElementSetAttributeValue(e, n as CFString, kCFBooleanTrue) == .success
    }
    private func setScroll(_ bar: AXUIElement, _ pos: Double) {
        AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, pos as CFNumber)
    }

    private func allWindows() -> [AXUIElement] {
        apps.flatMap { attr($0, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
            .filter { (attr($0, kAXMinimizedAttribute) as? Bool) != true }
    }
    /// The window that holds the chat list. Not simply the biggest one: an open sheet or document can be bigger.
    private var chatWindow: AXUIElement?
    private func mainWindow() -> AXUIElement? { layout().conv != nil ? chatWindow : nil }
    private func areas(_ e: AXUIElement, _ depth: Int = 0, _ out: inout [AXUIElement]) {
        if depth > 8 { return }
        for c in kids(e) {
            let r = role(c)
            if r == "AXScrollArea" { out.append(c) } else if r != "AXTable" { areas(c, depth + 1, &out) }
        }
    }
    private func table(in area: AXUIElement) -> AXUIElement? { kids(area).first { role($0) == "AXTable" } }

    private struct Layout { var side: AXUIElement?; var conv: AXUIElement?; var convArea: AXUIElement?; var msg: AXUIElement?; var msgArea: AXUIElement? }
    /// Layout is asked for at every scroll step, so the last good window is tried first.
    private func layout() -> Layout {
        if let w = chatWindow { let l = layout(in: w); if l.conv != nil { return l } }
        for w in allWindows().sorted(by: { frame($0).height > frame($1).height }) where w != chatWindow {
            // The narrow navigation column is only in the main window; a sheet can also have a list of that width.
            let l = layout(in: w)
            if l.conv != nil && l.side != nil { chatWindow = w; return l }
        }
        return Layout()
    }
    private func layout(in w: AXUIElement) -> Layout {
        var l = Layout()
        var found: [AXUIElement] = []
        areas(w, 0, &found)
        let withTables = found.compactMap { a in table(in: a).map { (a, $0, frame(a)) } }
        if let s = withTables.first(where: { $0.2.width < 100 }) { l.side = s.1 }
        // Other tabs have a list of the same width but it does not fill the window.
        let tall = frame(w).height * 0.75
        if let c = withTables.first(where: { $0.2.width >= 200 && $0.2.width < 320 && $0.2.height >= tall }) {
            l.conv = c.1; l.convArea = c.0
            if let m = withTables.filter({ $0.2.minX >= c.2.maxX - 2 && $0.2.width >= 200 }).max(by: { $0.2.width < $1.2.width }) {
                l.msg = m.1; l.msgArea = m.0
            }
        }
        return l
    }
    private func rows(_ t: AXUIElement) -> [AXUIElement] { attr(t, kAXRowsAttribute) as? [AXUIElement] ?? [] }

    private func flat(_ e: AXUIElement, _ out: inout [AXItem]) {
        for c in kids(e) {
            let r = role(c), f = frame(c)
            switch r {
            case "AXStaticText", "AXTextArea", "AXTextField":
                out.append(AXItem(r: r == "AXTextField" ? "AXTextArea" : r, v: str(c, kAXValueAttribute), x: Int(f.minX), w: Int(f.width)))
            case "AXLink":
                out.append(AXItem(r: r, v: str(c, kAXTitleAttribute), x: Int(f.minX), w: Int(f.width)))
            case "AXImage":
                out.append(AXItem(r: r, v: str(c, kAXDescriptionAttribute), x: Int(f.minX), w: Int(f.width)))
            case "AXButton":
                out.append(AXItem(r: r, v: str(c, kAXTitleAttribute), x: Int(f.minX), w: Int(f.width)))
            default: break
            }
            flat(c, &out)
        }
    }
    private func items(_ row: AXUIElement) -> [AXItem] { var o: [AXItem] = []; flat(row, &o); return o }
    private func convTexts(_ row: AXUIElement) -> [String] {
        items(row).filter { $0.r == "AXStaticText" && !$0.v.isEmpty }.map(\.v)
    }
    /// The unread count is a button over the avatar; the mute bell is a small image on the right.
    private func convRow(_ row: AXUIElement) -> ConvRow? {
        let all = items(row), left = Int(frame(row).minX)
        let t = all.filter { $0.r == "AXStaticText" && !$0.v.isEmpty }.map(\.v)
        guard let name = t.first else { return nil }
        return ConvRow(name: name, preview: t.count > 1 ? t[1] : "",
                       badge: all.contains { $0.r == "AXButton" && $0.x - left < 69 },
                       muted: all.contains { $0.r == "AXImage" && $0.w == 14 && $0.x - left > 150 },
                       element: row)
    }

    // MARK: tabs and conversations

    var onMessagesTab: Bool { layout().conv != nil }

    var conversationRows: Int { layout().conv.map { rows($0).count } ?? 0 }
    /// Pane sizes only, for the log.
    func describe() -> String {
        let windows = allWindows()
        guard let w = mainWindow() ?? windows.max(by: { frame($0).height < frame($1).height }) else { return "windows 0" }
        var found: [AXUIElement] = []
        areas(w, 0, &found)
        let sizes = found.map { "\(Int(frame($0).minX)):\(Int(frame($0).width))x\(Int(frame($0).height))" }
        return "windows \(windows.count), main \(frame(w)), panes \(sizes)"
    }
    private func pause(_ seconds: Double, _ stop: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !stop() { Thread.sleep(forTimeInterval: 0.05) }
    }
    private func listBar() -> AXUIElement? {
        layout().convArea.flatMap { attr($0, kAXVerticalScrollBarAttribute) }.map { $0 as! AXUIElement }
    }
    var listPosition: Double? { listBar().flatMap { attr($0, kAXValueAttribute) as? Double } }
    func scrollList(to pos: Double) { if let b = listBar() { setScroll(b, pos) } }
    /// Newest conversations are at the top, which is where the user looks.
    func listToTop() { scrollList(to: 0) }
    /// How far the list is scrolled, in points. A proportion means something else once more rows have loaded.
    var listOffset: Double? {
        let l = layout()
        guard let pos = listPosition, let c = l.conv, let a = l.convArea else { return nil }
        return pos * Double(max(frame(c).height - frame(a).height, 0))
    }
    func scrollList(toOffset y: Double) {
        let l = layout()
        guard let c = l.conv, let a = l.convArea else { return }
        let range = Double(frame(c).height - frame(a).height)
        scrollList(to: range > 0 ? min(max(y / range, 0), 1) : 0)
    }
    /// The list loads 50 more rows each time it reaches the bottom.
    func loadAllConversations(stop: () -> Bool) {
        var last = -1, same = 0
        for _ in 0..<200 where same < 3 {
            if stop() { return }
            guard let b = listBar(), let c = layout().conv else { return }
            setScroll(b, 1)
            pause(0.5, stop)
            let n = rows(c).count
            same = n == last ? same + 1 : 0
            last = n
        }
    }
    /// Reading every row is slow on a long list, so this gives up as soon as it must stop.
    func conversations(stop: () -> Bool = { false }) -> [ConvRow] {
        guard let c = layout().conv else { return [] }
        var out: [ConvRow] = []
        for r in rows(c) {
            if stop() { break }
            if let row = convRow(r) { out.append(row) }
        }
        return out
    }
    func selectedRow() -> ConvRow? {
        guard let c = layout().conv, let sel = (attr(c, kAXSelectedRowsAttribute) as? [AXUIElement])?.first else { return nil }
        return convRow(sel)
    }
    /// Hands the conversation back without waiting for it to load, so WeCom is free at once.
    func selectQuickly(_ r: ConvRow) {
        var target: AXUIElement? = r.element
        if convTexts(r.element).first != r.name {
            // Only the rows on screen: walking the whole list takes seconds and the user is waiting.
            target = layout().conv.flatMap { c in (attr(c, kAXVisibleRowsAttribute) as? [AXUIElement] ?? []).first { convTexts($0).first == r.name } }
        }
        if let target, let row = convRow(target), mayOpen(row.facts) { _ = setBool(target, kAXSelectedAttribute) }
    }
    func selectedConversation() -> String? {
        guard let c = layout().conv, let sel = (attr(c, kAXSelectedRowsAttribute) as? [AXUIElement])?.first else { return nil }
        return convTexts(sel).first
    }
    /// Selects without bringing WeCom forward. Row elements can be reused, so the name is checked first.
    func select(_ r: ConvRow, stop: () -> Bool) -> SelectResult {
        var target = r.element
        if convTexts(target).first != r.name {
            var fresh = conversations(stop: stop).first { $0.name == r.name }
            if fresh == nil && !stop() {
                // The list can drop back to its first 50 rows.
                loadAllConversations(stop: stop)
                fresh = conversations(stop: stop).first { $0.name == r.name }
            }
            guard let found = fresh else { return stop() ? .interrupted : .noRow }
            target = found.element
        }
        if stop() { return .interrupted }
        guard let live = convRow(target), mayOpen(live.facts) else { return .held }
        guard setBool(target, kAXSelectedAttribute) else { listToTop(); return .noRow }
        // The user glances at the list from the top; finding a row may have left it far down.
        listToTop()
        for _ in 0..<15 {
            pause(0.2, stop)
            if stop() { return .interrupted }
            if selectedConversation() == r.name, let m = layout().msg, !rows(m).isEmpty { pause(0.4, stop); return .ok }
        }
        return .noPane
    }
    /// The message pane's horizontal centre, used to tell own messages from others'.
    func messageMidX() -> Int { layout().msgArea.map { Int(frame($0).midX) } ?? 900 }

    // MARK: reading
    //
    // Rows are keyed by their distance from the newest message. Older history loads in at the top and shifts every
    // row number, but never this distance, so a read can be resumed and two reads can be compared.

    private func bar(_ l: Layout) -> AXUIElement? {
        l.msgArea.flatMap { attr($0, kAXVerticalScrollBarAttribute) }.map { $0 as! AXUIElement }
    }
    /// The whole conversation is loaded and visible: there is no scrollbar.
    var fitsOnScreen: Bool { let l = layout(); return l.msg != nil && bar(l) == nil }
    var loadedRows: Int { layout().msg.map { rows($0).count } ?? 0 }
    /// What the newest row says, to notice a message arriving in the middle of a read. Rows away from the viewport
    /// are blank, so it is always taken at the bottom.
    private func newestRow(_ stop: () -> Bool) -> [AXItem]? {
        scrollToNewest()
        pause(0.25, stop)
        return layout().msg.flatMap { rows($0).last }.map(items)
    }

    /// Loads older messages until `rows` are loaded, the top is reached, or `maxSteps` loads. True at the top.
    @discardableResult
    func loadOlder(maxSteps: Int, untilRows target: Int = .max, stop: () -> Bool) -> Bool {
        var same = 0
        for _ in 0..<maxSteps {
            if stop() { return false }
            let l = layout()
            guard let m = l.msg else { return false }
            // A short conversation has no scrollbar, so everything is already loaded.
            guard let b = bar(l) else { return true }
            let before = rows(m).count
            if before >= target { return false }
            setScroll(b, 0.05)
            pause(0.1, stop)
            setScroll(b, 0.0)
            // Wait for the rows instead of a fixed time: usually much faster, and slow loads still get time.
            var grew = false
            for _ in 0..<15 { pause(0.1, stop); if stop() { return false }; if rows(m).count > before { grew = true; break } }
            same = grew ? 0 : same + 1
            if same >= 8 { return true }
        }
        return false
    }

    private func score(_ r: [AXItem]) -> Int { r.reduce(0) { $0 + $1.v.count + 1 } }
    private func collect(_ m: AXUIElement, into store: inout [Int: [AXItem]], stop: () -> Bool) {
        let total = rows(m).count
        for r in attr(m, kAXVisibleRowsAttribute) as? [AXUIElement] ?? [] {
            if stop() { return }
            guard let i = attr(r, kAXIndexAttribute) as? Int else { continue }
            let key = total - i
            let d = items(r)
            if score(d) > (store[key].map(score) ?? -1) { store[key] = d }
        }
    }
    private func visible(_ m: AXUIElement) -> [Int] {
        (attr(m, kAXVisibleRowsAttribute) as? [AXUIElement] ?? []).compactMap { attr($0, kAXIndexAttribute) as? Int }
    }
    /// Walks the pane between two scroll positions. Row heights are only estimates until rows are drawn, so a
    /// fixed step can jump over rows; each step is checked to overlap the one before and halved when it does not.
    private func walk(from start: Double, to end: Double, into store: inout [Int: [AXItem]], stop: () -> Bool) -> Bool {
        var pos = start
        let down = end > start
        var lastSeen: [Int] = []
        var step: Double?
        while true {
            if stop() { return false }
            let l = layout()
            guard let m = l.msg, let a = l.msgArea else { return false }
            guard let b = bar(l) else { collect(m, into: &store, stop: stop); return !stop() }
            setScroll(b, min(max(pos, 0), 1))
            pause(0.2, stop)
            let seen = visible(m)
            if let lo = lastSeen.min(), let hi = lastSeen.max(), let s = step, s > 0.0005, !seen.isEmpty,
               down ? seen.min()! > hi + 1 : seen.max()! < lo - 1 {
                // Jumped past rows: go back half a step.
                step = s / 2
                pos += down ? -s / 2 : s / 2
                continue
            }
            collect(m, into: &store, stop: stop)
            if !seen.isEmpty { lastSeen = seen }
            let v = frame(a).height, h = frame(m).height
            if h <= v { return true }
            if step == nil { step = Double(v * 0.7 / (h - v)) }
            if down ? pos >= end : pos <= end { return true }
            pos += down ? step! : -step!
            // A step that was halved grows back, so a long walk does not crawl.
            step = min(step! * 1.25, Double(v * 0.7 / (h - v)))
        }
    }
    /// Scrolls until the row at `index` is on screen. False if it cannot be brought into view.
    private func bringIntoView(_ index: Int, stop: () -> Bool) -> Bool {
        for _ in 0..<10 {
            if stop() { return false }
            let l = layout()
            guard let m = l.msg, let b = bar(l), let pos = attr(b, kAXValueAttribute) as? Double else { return l.msg != nil && bar(l) == nil }
            let seen = visible(m)
            if seen.contains(index) { return true }
            let total = max(rows(m).count - 1, 1)
            let mid = seen.isEmpty ? Int(pos * Double(total)) : (seen.min()! + seen.max()!) / 2
            setScroll(b, min(max(pos + Double(index - mid) / Double(total), 0), 1))
            pause(0.25, stop)
        }
        return false
    }
    /// Rows that came back empty are brought into view one by one. A row that is on screen and still has nothing in
    /// it really is empty; one that cannot be brought into view fails the read rather than going missing.
    private func refill(_ store: inout [Int: [AXItem]], keys: ClosedRange<Int>, stop: () -> Bool) -> Bool {
        for k in keys where (store[k] ?? []).isEmpty {
            if stop() { return false }
            guard let m = layout().msg else { return false }
            let total = rows(m).count
            guard k >= 1 && k <= total else { continue }
            guard bringIntoView(total - k, stop: stop) else { return false }
            pause(0.2, stop)
            guard let m2 = layout().msg else { return false }
            collect(m2, into: &store, stop: stop)
            if store[k] == nil { store[k] = [] }
        }
        return !stop()
    }
    /// Rows from `nearest` to `farthest` (1 is the newest), oldest first. Nil when interrupted, when the pane went
    /// away, or when a new message arrived during the read (every distance would be off by one).
    private func read(nearest: Int, farthest: Int, stop: () -> Bool) -> [[AXItem]]? {
        // A busy group can get a message during a read; try again a couple of times before giving up.
        for _ in 0..<3 {
            if let r = readOnce(nearest: nearest, farthest: farthest, stop: stop) { return r }
            if stop() { return nil }
        }
        return nil
    }
    private func readOnce(nearest: Int, farthest: Int, stop: () -> Bool) -> [[AXItem]]? {
        let l = layout()
        guard let m = l.msg else { return nil }
        let total = rows(m).count
        let far = min(farthest, total)
        guard far >= nearest else { return [] }
        let newest = newestRow(stop)
        var store: [Int: [AXItem]] = [:]
        let span = Double(max(total - 1, 1))
        // Scroll positions run from 0 at the oldest loaded row to 1 at the newest.
        let lo = Double(total - far) / span, hi = Double(total - nearest) / span
        guard walk(from: hi, to: max(lo - 0.01, 0), into: &store, stop: stop),
              refill(&store, keys: nearest...far, stop: stop) else { return nil }
        if stop() || newestRow(stop) != newest { return nil }
        return (nearest...far).reversed().compactMap { store[$0] }
    }
    /// About how many rows fill `screens` screens of the message pane.
    func rows(screens: Int) -> Int { layout().msgArea.map { screens * max(1, Int(frame($0).height) / 40) } ?? screens * 15 }
    /// The newest `screens` of the conversation.
    func readTail(screens: Int, stop: () -> Bool) -> [[AXItem]]? {
        let l = layout()
        guard let m = l.msg, let a = l.msgArea else { return nil }
        let total = rows(m).count, perScreen = max(1, Int(frame(a).height) / 40)
        return read(nearest: 1, farthest: min(total, screens * perScreen), stop: stop)
    }
    /// Rows at the given distances from the newest, for reading a stretch of older history.
    func readRange(nearest: Int, farthest: Int, stop: () -> Bool) -> [[AXItem]]? {
        read(nearest: nearest, farthest: farthest, stop: stop)
    }
    func scrollToNewest() {
        let l = layout()
        if let b = bar(l) { setScroll(b, 1) }
    }
}
