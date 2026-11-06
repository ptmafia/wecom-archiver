import Foundation

/// One accessibility element inside a message row, flattened in tree order.
public struct AXItem: Codable, Equatable {
    public var r: String
    public var v: String
    public var x: Int
    public var w: Int
    public init(r: String, v: String, x: Int, w: Int) { self.r = r; self.v = v; self.x = x; self.w = w }
}

public struct Quote: Codable, Equatable {
    public var name: String
    public var text: String
    public init(name: String, text: String) { self.name = name; self.text = text }
}

public struct Attachment: Codable, Equatable {
    public var name: String
    public var size: String
    public init(name: String, size: String) { self.name = name; self.size = size }
}

/// `gap` marks a stretch of history that has not been read yet; it is never a real message.
public enum Kind: String, Codable { case text, image, file, system, gap }

public struct Message: Codable, Equatable {
    public var at: String?
    public var sender: String
    public var kind: Kind
    public var text: String
    public var quote: Quote?
    public var notify: String?
    public var files: [Attachment]
    public var links: [String]

    public init(at: String?, sender: String, kind: Kind, text: String, quote: Quote? = nil,
                notify: String? = nil, files: [Attachment] = [], links: [String] = []) {
        self.at = at; self.sender = sender; self.kind = kind; self.text = text
        self.quote = quote; self.notify = notify; self.files = files; self.links = links
    }

    /// Time is left out on purpose: WeCom shows it only on some rows.
    public var fingerprint: String {
        "\(sender)|\(kind.rawValue)|\(text)|\(files.map(\.name).joined(separator: ","))"
    }
}

public enum TimeParser {
    private static let weekdays: [String: Int] = [
        "日曜日": 1, "月曜日": 2, "火曜日": 3, "水曜日": 4, "木曜日": 5, "金曜日": 6, "土曜日": 7,
        "星期日": 1, "星期天": 1, "星期一": 2, "星期二": 3, "星期三": 4, "星期四": 5, "星期五": 6, "星期六": 7,
        "週日": 1, "週一": 2, "週二": 3, "週三": 4, "週四": 5, "週五": 6, "週六": 7,
        "周日": 1, "周一": 2, "周二": 3, "周三": 4, "周四": 5, "周五": 6, "周六": 7,
        "Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7,
        "Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7,
    ]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        let re = try! NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
    private static func format(_ c: DateComponents, _ hour: Int, _ minute: Int) -> String {
        String(format: "%04d-%02d-%02d %02d:%02d", c.year!, c.month!, c.day!, hour, minute)
    }

    /// Converts WeCom's relative timestamps to "yyyy-MM-dd HH:mm". Returns nil for anything else.
    public static func parse(_ raw: String, now: Date) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.dateComponents([.year, .month, .day], from: now)

        // 24-hour, or 12-hour with a marker before (午後 3:20, 下午3:20) or after (3:20 PM).
        guard let t = match(#"(午前|午後|上午|下午|中午|晚上|凌晨|早上)?\s*(\d{1,2}):(\d{2})\s*([AaPp]\.?[Mm]\.?)?$"#, s),
              var h = Int(t[2]), let mi = Int(t[3]), h < 24, mi < 60 else { return nil }
        let marker = t[1] + t[4].uppercased().replacingOccurrences(of: ".", with: "")
        if !marker.isEmpty {
            guard h >= 1 && h <= 12 else { return nil }
            let pm = ["午後", "下午", "晚上", "PM"].contains(marker) || (marker == "中午" && h < 3)
            h = pm ? (h % 12) + 12 : h % 12
        }
        let head = s.dropLast(t[0].count).trimmingCharacters(in: .whitespaces)
        func back(_ days: Int) -> String {
            format(cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: -days, to: now)!), h, mi)
        }
        if head.isEmpty || ["今日", "今天", "Today"].contains(head) { return format(today, h, mi) }
        if ["昨日", "昨天", "Yesterday"].contains(head) { return back(1) }
        if let wd = weekdays[head] {
            let todayWd = cal.component(.weekday, from: now)
            let diff = (todayWd - wd + 7) % 7
            return back(diff == 0 ? 7 : diff)
        }
        if let d = match(#"^([A-Z][a-z]{2}) (\d{1,2}), (\d{4})$"#, head), let mo = months.firstIndex(of: d[1]) {
            return format(DateComponents(year: Int(d[3]), month: mo + 1, day: Int(d[2])), h, mi)
        }
        if let d = match(#"^([A-Z][a-z]{2}) (\d{1,2}),?$"#, head), let mo = months.firstIndex(of: d[1]), let da = Int(d[2]) {
            var c = DateComponents(year: today.year, month: mo + 1, day: da)
            if let date = cal.date(from: c), date > now { c.year = today.year! - 1 }
            return format(c, h, mi)
        }
        if let d = match(#"^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$"#, head) {
            return format(DateComponents(year: Int(d[1]), month: Int(d[2]), day: Int(d[3])), h, mi)
        }
        if let d = match(#"^(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?$"#, head) {
            return format(DateComponents(year: Int(d[1]), month: Int(d[2]), day: Int(d[3])), h, mi)
        }
        if let d = match(#"^(\d{1,2})月\s*(\d{1,2})日?$"#, head), let mo = Int(d[1]), let da = Int(d[2]) {
            var c = DateComponents(year: today.year, month: mo, day: da)
            if let date = cal.date(from: c), date > now { c.year = today.year! - 1 }
            return format(c, h, mi)
        }
        return nil
    }
}

public enum RowParser {
    /// Buttons inside a message row that are not the sender's name, in each UI language.
    private static let ignoredButtons: Set<String> = ["ボタン", "記録の表示", "按钮", "按鈕", "Button", "button",
                                                      "查看录制", "檢視錄製", "View Recording", ""]

    /// Turns raw rows into messages. Rows without their own timestamp inherit the one before them.
    public static func assemble(_ rows: [[AXItem]], selfName: String, peerName: String? = nil,
                                midX: Int = 900, now: Date) -> [Message] {
        var out: [Message] = []
        var lastTime: String?
        for items in rows {
            var name = "", texts: [String] = [], links: [String] = [], files: [Attachment] = []
            var quoteName: String?, quoteTitle: String?, avatarX: Int?, pictures = 0
            var pendingFile = false, fileName: String?
            for i in items {
                let v = i.v.trimmingCharacters(in: .whitespacesAndNewlines)
                switch i.r {
                case "AXStaticText":
                    if v.isEmpty { continue }
                    // Messages never go back in time, so an earlier "time" is something else, like a video's length.
                    if let t = TimeParser.parse(v, now: now) { if lastTime.map({ t >= $0 }) ?? true { lastTime = t } }
                    else if v.hasSuffix(":") || v.hasSuffix("：") { quoteName = String(v.dropLast()) }
                    else if pendingFile {
                        if let n = fileName { files.append(Attachment(name: n, size: v)); fileName = nil; pendingFile = false }
                        else { fileName = v }
                    }
                    else if quoteName != nil && quoteTitle == nil { quoteTitle = v }
                case "AXButton":
                    if name.isEmpty && !ignoredButtons.contains(v) { name = v }
                case "AXTextArea":
                    if !v.isEmpty { texts.append(v) }
                case "AXLink":
                    if !v.isEmpty { links.append(v) }
                case "AXImage":
                    if v.hasPrefix("file") { pendingFile = true }
                    else if avatarX == nil && i.w <= 30 { avatarX = i.x }
                    else { pictures += 1 }
                default: break
                }
            }
            if let n = fileName { files.append(Attachment(name: n, size: "")) }
            let sender: String
            if !name.isEmpty { sender = name }
            else if let x = avatarX { sender = x > midX ? selfName : (peerName ?? "未知") }
            else { sender = texts.isEmpty && pictures > 0 ? selfName : "系统消息" }

            var main = texts.last ?? "", quote: Quote?, notify: String?
            if let q = quoteName {
                if texts.count >= 2 { quote = Quote(name: q, text: texts[texts.count - 2]) }
                else if !main.isEmpty, let f = files.first { quote = Quote(name: q, text: "［文件］\(f.name)"); files = [] }
                else { quote = Quote(name: q, text: quoteTitle ?? "") }
                if texts.count >= 3 { notify = texts[0] }
            } else if texts.count >= 2 {
                if !texts[0].contains("\n") && texts[0].count < 80 { notify = texts[0]; main = texts.dropFirst().joined(separator: "\n") }
                else { main = texts.joined(separator: "\n") }
            }
            let kind: Kind
            if !files.isEmpty { kind = .file }
            else if !main.isEmpty { kind = sender == "系统消息" ? .system : .text }
            else if pictures > 0 || avatarX != nil || !name.isEmpty { kind = .image }
            else { continue }
            out.append(Message(at: lastTime, sender: sender, kind: kind, text: main, quote: quote,
                               notify: notify, files: files, links: links))
        }
        return out
    }
}

public struct MergeResult: Equatable {
    public var merged: [Message]
    /// Real messages that were not in the archive before.
    public var added: Int
    /// The archive still has stretches that were never read.
    public var gaps: Int
}

/// Combines what was just read with the archive.
///
/// Two reads are placed against each other only where a whole run of messages lines up, never on the last few
/// alone: a group often repeats the same pictures or 「好的」, and lining up on those would drop what was between.
/// A read that lines up with nothing is kept as its own stretch with a gap marker, so nothing is lost or reordered.
public enum Merger {
    public static let gap = Message(at: nil, sender: "", kind: .gap, text: "")

    public enum Position { case newest, oldest }

    /// Where b sits inside a, as b[i] == a[i + offset], with the length of the overlap.
    struct Alignment { let offset: Int; let length: Int; let matches: Int }

    static func align(_ a: [Message], _ b: [Message]) -> Alignment? {
        if a.isEmpty || b.isEmpty { return nil }
        let fa = a.map(\.fingerprint), fb = b.map(\.fingerprint)
        var at: [String: [Int]] = [:]
        for (i, f) in fa.enumerated() { at[f, default: []].append(i) }
        // Candidate offsets come from b's ends, which are the parts that can overlap a.
        var candidates = Set<Int>()
        for i in Array(fb.indices.prefix(40)) + Array(fb.indices.suffix(40)) {
            for j in (at[fb[i]] ?? []).suffix(400) { candidates.insert(j - i) }
        }
        var best: Alignment?, tied: [Alignment] = []
        let b0 = b
        for o in candidates {
            let lo = max(0, -o), hi = min(fb.count, fa.count - o)
            let length = hi - lo
            guard length > 0 else { continue }
            var matches = 0, kinds = Set<String>()
            for i in lo..<hi where fb[i] == fa[i + o] { matches += 1; kinds.insert(fb[i]) }
            let shorter = min(fa.count, fb.count)
            // At least three in a row: two common replies such as 「好的」「收到」 line up by chance.
            // Short overlaps must match exactly; long ones may differ a little (a recalled or edited message).
            let enough = length >= min(3, shorter) && (length - matches) <= (length >= 10 ? length / 10 : 0)
            // A run of identical pictures lines up anywhere, so the overlap must hold at least two different messages
            // unless it is the whole of the shorter read.
            let distinct = kinds.count >= 2 || length == shorter
            // Differences are only allowed inside the overlap. At its ends they mean one read is shifted against
            // the other (a row missing), and lining up anyway would overwrite a message.
            let endsHold = length < 10 || [lo, lo + 1, hi - 2, hi - 1].allSatisfy { fb[$0] == fa[$0 + o] }
            guard enough && distinct && endsHold else { continue }
            let c = Alignment(offset: o, length: length, matches: matches)
            if let b = best {
                if c.matches > b.matches { best = c; tied = [] } else if c.matches == b.matches { tied.append(c) }
            } else { best = c }
        }
        // Several equally good places: fine when they all give the same result (a read already in the archive twice).
        if let b = best, !tied.isEmpty {
            let result = union(a, b0, b)
            return tied.allSatisfy { union(a, b0, $0) == result } ? b : nil
        }
        return best
    }

    /// The union of two lined-up reads. Where they differ, the fuller version wins.
    static func union(_ a: [Message], _ b: [Message], _ al: Alignment) -> [Message] {
        let start = min(0, al.offset), end = max(a.count, b.count + al.offset)
        return (start..<end).map { k in
            let x = k >= 0 && k < a.count ? a[k] : nil
            let i = k - al.offset
            let y = i >= 0 && i < b.count ? b[i] : nil
            switch (x, y) {
            // Where they differ, what was saved stays, unless it came out empty and the new read has it.
            case let (x?, y?): return x.fingerprint == y.fingerprint || (x.text.isEmpty && !y.text.isEmpty) ? y : x
            case let (x?, nil): return x
            case let (nil, y?): return y
            default: fatalError("unreachable")
            }
        }
    }

    public static func segments(_ archive: [Message]) -> [[Message]] {
        archive.split(omittingEmptySubsequences: true, whereSeparator: { $0.kind == .gap }).map(Array.init)
    }

    /// - Parameters:
    ///   - position: where the fresh read sits if it lines up with nothing. Every read that ends at the newest
    ///     message is `.newest`.
    ///   - complete: the fresh read runs from the very first message to the newest, with no row missing.
    public static func combine(existing: [Message], fresh: [Message], position: Position = .newest, complete: Bool = false) -> MergeResult {
        let real = existing.filter { $0.kind != .gap }.count
        var segs = segments(existing)
        if !fresh.isEmpty {
            let order = position == .newest ? Array(segs.indices.reversed()) : Array(segs.indices)
            if let i = order.first(where: { align(segs[$0], fresh) != nil }) {
                segs[i] = union(segs[i], fresh, align(segs[i], fresh)!)
                // The grown stretch may now reach its neighbours.
                var j = 0
                while j + 1 < segs.count {
                    if let al = align(segs[j], segs[j + 1]) { segs[j] = union(segs[j], segs[j + 1], al); segs.remove(at: j + 1) }
                    else { j += 1 }
                }
            } else if position == .newest { segs.append(fresh) } else { segs.insert(fresh, at: 0) }
        }
        // A complete read is the whole conversation as WeCom shows it now, so it goes last. Stretches it cannot place
        // (history cleared on this Mac, or an old misplaced read) stay in front of it: nothing is dropped.
        if complete, let w = segs.firstIndex(where: { s in s.count >= fresh.count && align(s, fresh).map { $0.length == fresh.count } ?? false }) {
            let whole = segs.remove(at: w)
            segs.append(whole)
        }
        var merged: [Message] = []
        for (i, s) in segs.enumerated() { if i > 0 { merged.append(gap) }; merged += s }
        let now = merged.filter { $0.kind != .gap }.count
        return MergeResult(merged: merged, added: max(0, now - real), gaps: max(0, segs.count - 1))
    }
}

/// When reading may start. Reading changes what WeCom shows, so it waits until WeCom has been left alone.
public enum Schedule {
    public static let quietSeconds: TimeInterval = 60
    public static func mayRead(locked: Bool, wecomInFront: Bool, lastInFront: Date, now: Date) -> Bool {
        !locked && !wecomInFront && now.timeIntervalSince(lastInFront) >= quietSeconds
    }
}

public struct ConvState: Codable, Equatable {
    public var signature: String
    /// Read from the first message to the newest, with no gap left.
    public var complete: Bool
    public var attempts: Int
    public var count: Int
    public var lastRead: String
    /// Kept for state files written before `reach`; no longer used.
    public var depth: Int
    /// How many rows back from the newest the history has been read, so an interrupted read resumes there.
    public var reach: Int
    /// A conversation that would not open is left until then ("yyyy-MM-dd HH:mm:ss").
    public var retryAfter: String?
    /// `Priority.score` as of the last read; nil until read once.
    public var value: Double?
    public init(signature: String = "", complete: Bool = false, attempts: Int = 0, count: Int = 0, lastRead: String = "",
                depth: Int = 0, reach: Int = 0, retryAfter: String? = nil, value: Double? = nil) {
        self.signature = signature; self.complete = complete; self.attempts = attempts; self.count = count
        self.lastRead = lastRead; self.depth = depth; self.reach = reach; self.retryAfter = retryAfter; self.value = value
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(signature: try c.decode(String.self, forKey: .signature), complete: try c.decode(Bool.self, forKey: .complete),
                  attempts: try c.decode(Int.self, forKey: .attempts), count: try c.decode(Int.self, forKey: .count),
                  lastRead: try c.decode(String.self, forKey: .lastRead), depth: try c.decodeIfPresent(Int.self, forKey: .depth) ?? 0,
                  reach: try c.decodeIfPresent(Int.self, forKey: .reach) ?? 0,
                  retryAfter: try c.decodeIfPresent(String.self, forKey: .retryAfter),
                  value: try c.decodeIfPresent(Double.self, forKey: .value))
    }
}

/// How much a conversation is worth reading in full, from what is already saved. Only things every install has are
/// used: how much the owner takes part, mentions, how small the circle is, files, how recent; plus optional words
/// the owner cares about (`priority-words.txt`). Notifications and big groups the owner never speaks in score low.
public enum Priority {
    public enum Tier: String { case high, mid, low }
    public static func tier(_ score: Double) -> Tier { score >= 4 ? .high : score >= 1.5 ? .mid : .low }

    public static func score(_ messages: [Message], selfName: String, words: [String] = [], name: String = "", now: Date) -> Double {
        let real = messages.filter { $0.kind != .gap }
        let human = real.filter { $0.kind != .system }
        guard !human.isEmpty else { return 0 }
        let own = human.filter { $0.sender == selfName }.count
        let people = Set(human.map(\.sender)).subtracting([selfName, "系统消息", "未知", ""]).count
        let mentions = selfName == "我" ? 0 : human.filter { $0.text.contains("@\(selfName)") }.count
        let files = real.filter { $0.kind == .file }.count
        let hits = words.isEmpty ? 0 : human.filter { m in words.contains { m.text.contains($0) } }.count
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let last = real.compactMap { $0.at.flatMap(f.date(from:)) }.max()
        let recent = last.map { now.timeIntervalSince($0) < 14 * 86400 } ?? false

        var s = 4 * min(Double(own) / Double(human.count) / 0.3, 1)
        s += 2 * min(Double(mentions) / 5, 1)
        s += people <= 1 ? 1.5 : people <= 10 ? 1 : 0.3
        s += min(Double(files) / 5, 1)
        s += recent ? 1 : 0
        s += 1.5 * min(Double(hits) / 10, 1)
        // Named after a store, project or client the owner cares about: worth it even if the owner only reads.
        let named = words.contains { name.contains($0) }
        if named { s += 1.5 }
        // Never answered, never mentioned: a notification feed, or a crowd the owner only listens to.
        else if own == 0 && mentions == 0 { s *= people <= 1 ? 0.3 : 0.5 }
        return s
    }

    /// A guess for a conversation not read yet, from its list row: a private chat, or a group where the owner or a
    /// known colleague spoke last, comes first.
    public static func estimate(name: String, sender: String?, selfName: String, known: Set<String>, words: [String] = []) -> Double {
        var s: Double
        if let who = sender { s = who == selfName ? 3 : known.contains(who) ? 2 : 1.5 } else { s = 3 }
        if words.contains(where: { name.contains($0) }) { s += 1.5 }
        return s
    }
}

/// Where an install stands. Just installed: most conversations never read, so every one first gets its newest
/// messages. Then the history of what matters. Then day to day: keeping up.
public enum Stage: String {
    case start, history, daily
    public static func of(total: Int, neverRead: Int, historyLeft: Int) -> Stage {
        if neverRead > max(10, total / 10) { return .start }
        return historyLeft > 0 ? .history : .daily
    }
}

/// Senders that prove a list row is a group. Taken from conversations with at least three different people, so a
/// private chat's own two names never count, and conversation names are left out: a private message can start with
/// a colleague's name followed by a colon.
public enum GroupMembers {
    public static func from(_ archive: [(conv: String, messages: [Message])], selfName: String) -> Set<String> {
        var out = Set<String>()
        for (_, ms) in archive {
            let people = Set(ms.filter { $0.kind != .system && $0.kind != .gap }.map(\.sender))
                .subtracting([selfName, "系统消息", "未知", ""])
            if people.count >= 2 { out.formUnion(people) }
        }
        return out
    }
}

public struct Archive {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/wecom-reader")
    }
    public var dir: URL { root.appendingPathComponent("archive") }
    public var statePath: URL { root.appendingPathComponent("state.json") }

    public static func fileName(_ conv: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\n\r\t\0")
        let clean = conv.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
        let cut = String(clean.prefix(100)).trimmingCharacters(in: .whitespaces)
        return (cut.isEmpty || cut.hasPrefix(".") ? "_" + cut : cut) + ".jsonl"
    }

    public func prepare() throws {
        for d in [root, dir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        }
    }
    /// Every conversation on disk, named by its file.
    public func loadAll() -> [(conv: String, messages: [Message])] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".jsonl") }.sorted().map { f in
            let conv = String(f.dropLast(".jsonl".count))
            return (conv, load(conv))
        }
    }
    public func load(_ conv: String) -> [Message] {
        guard let s = try? String(contentsOf: dir.appendingPathComponent(Self.fileName(conv)), encoding: .utf8) else { return [] }
        let d = JSONDecoder()
        return s.split(separator: "\n").compactMap { try? d.decode(Message.self, from: Data($0.utf8)) }
    }
    public func exists(_ conv: String) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(Self.fileName(conv)).path) }
    /// Nil when a line cannot be read, so the file is not rewritten without it. Empty when there is no file.
    public func loadIntact(_ conv: String) -> [Message]? {
        guard let s = try? String(contentsOf: dir.appendingPathComponent(Self.fileName(conv)), encoding: .utf8) else { return [] }
        let d = JSONDecoder()
        var out: [Message] = []
        for line in s.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let m = try? d.decode(Message.self, from: Data(line.utf8)) else { return nil }
            out.append(m)
        }
        return out
    }
    public func save(_ conv: String, _ messages: [Message]) throws {
        let e = JSONEncoder(); e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let body = try messages.map { String(decoding: try e.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let url = dir.appendingPathComponent(Self.fileName(conv))
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Nil when the file is there but cannot be read: starting over from nothing would re-read every conversation.
    public func loadState() -> [String: ConvState]? {
        guard FileManager.default.fileExists(atPath: statePath.path) else { return [:] }
        guard let d = try? Data(contentsOf: statePath) else { return nil }
        return try? JSONDecoder().decode([String: ConvState].self, from: d)
    }
    /// A copy of the archive and state once a day, kept for a week. APFS copies are clones, so they cost almost no space.
    public func backUpDaily(now: Date = Date()) {
        let fm = FileManager.default
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let base = root.appendingPathComponent("backup")
        let today = base.appendingPathComponent(f.string(from: now))
        guard !fm.fileExists(atPath: today.path) else { return }
        try? fm.createDirectory(at: today, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        for item in ["archive", "state.json"] where fm.fileExists(atPath: root.appendingPathComponent(item).path) {
            try? fm.copyItem(at: root.appendingPathComponent(item), to: today.appendingPathComponent(item))
        }
        let old = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted().dropLast(7)
        for d in old { try? fm.removeItem(at: base.appendingPathComponent(d)) }
    }
    public func saveState(_ s: [String: ConvState]) throws {
        try JSONEncoder().encode(s).write(to: statePath, options: .atomic)
    }
}

extension Merger {
    /// Tail reads can start on rows without a timestamp; those take the time of the message before them.
    public static func fillTimes(_ messages: [Message]) -> [Message] {
        var out = messages
        var last: String?
        for i in out.indices where out[i].kind != .gap {
            if let t = out[i].at { last = t } else { out[i].at = last }
        }
        return out
    }
}

/// Plain search over the archive, for installs without the separate index.
public enum ChatSearch {
    public struct Hit: Equatable {
        public let conv: String
        public let at: String?
        public let sender: String
        public let excerpt: String
    }
    private static let contact = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\+?\d{1,3}[- ]?\d{1,4}[- ]\d{2,4}[- ]\d{3,4}|0\d{1,4}-\d{1,4}-\d{3,4}|\b0\d{9,10}\b|\b1[3-9]\d{9}\b"#)

    /// Results end up in an AI conversation, so phones and emails are hidden from what is shown.
    public static func mask(_ text: String) -> String {
        contact.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "［已打码］")
    }
    public static func matches(_ text: String, _ words: [String]) -> Bool {
        let t = text.lowercased()
        return !words.isEmpty && words.allSatisfy { t.contains($0.lowercased()) }
    }
    public static func excerpt(_ text: String, around word: String, size: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > size else { return flat }
        let at = flat.lowercased().range(of: word.lowercased()).map { flat.distance(from: flat.startIndex, to: $0.lowerBound) } ?? 0
        let start = max(0, min(at - size / 3, flat.count - size))
        let cut = String(flat.dropFirst(start).prefix(size))
        return (start > 0 ? "…" : "") + cut + (start + size < flat.count ? "…" : "")
    }
    /// Newest first.
    public static func find(_ words: [String], in archive: [(conv: String, messages: [Message])]) -> [Hit] {
        var hits: [Hit] = []
        for (conv, messages) in archive {
            for m in messages where m.kind == .text && matches(m.text, words) {
                hits.append(Hit(conv: conv, at: m.at, sender: m.sender, excerpt: excerpt(mask(m.text), around: words[0])))
            }
        }
        return hits.sorted { ($0.at ?? "") > ($1.at ?? "") }
    }
}

/// List entries that are not chats. Opening a folder replaces the conversation list, and opening a feature
/// entry jumps to another tab. Neither can be undone in the background, so they are never opened.
public enum ConversationList {
    private static let features: Set<String> = [
        "カレンダー", "日程", "日历", "Calendar", "メールボックス", "邮件", "邮箱", "Mailbox", "Mail", "Email", "WeDrive", "微盘",
        "ミーティング", "会议", "Meetings", "報告する", "汇报", "Reports", "会社の管理を行う", "管理企业", "知能ロボット", "智能机器人",
        "高度機能", "高级功能", "申請通知", "审批", "Approvals", "お知らせ", "公告", "Announcements",
    ]
    public static func isChat(_ name: String) -> Bool {
        !features.contains(name) && !["最小限のチャット", "最小化", "Minimized"].contains { name.contains($0) }
    }
}

/// What the conversation list shows about one row without opening it.
public struct RowFacts: Equatable {
    public let name: String
    public let preview: String
    /// The red count on the avatar.
    public let badge: Bool
    /// Notifications off. Such a row shows no badge, and a single unread message leaves no trace at all.
    public let muted: Bool
    public init(name: String, preview: String, badge: Bool, muted: Bool) {
        self.name = name; self.preview = preview; self.badge = badge; self.muted = muted
    }
}

/// Opening a conversation clears its unread mark, so the owner reads these first: anything private, and any
/// group that mentions them. Other groups may be read at once. When a row cannot be proven safe it stays closed.
public enum UnreadRule {
    /// The unread count WeCom puts in front of a muted chat: [3 メッセージ ], [3条], [3條], [3 messages].
    private static let countTag = try! NSRegularExpression(pattern: "^[\\[【]\\d+[^\\]】]*[\\]】]\\s*")
    private static func countTagLength(_ s: String) -> Int {
        countTag.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.range.length ?? 0
    }
    /// WeCom's own tags (Localizable.strings: RecentConversation.SomeoneAtMeDesc and AtAllDesc) in ja, zh-Hans,
    /// zh-Hant and en. "@all" counts because it reaches the owner too.
    static let mentionTags = ["[あなたが言及されました]", "[有人@我]", "[You were mentioned]", "[@全員]", "[@所有人]", "[@All]", "[@all]"]
    public static func mentioned(_ preview: String, selfName: String) -> Bool {
        let s = String(preview.utf16.dropFirst(countTagLength(preview))) ?? preview
        return mentionTags.contains { preview.contains($0) } || s.hasPrefix("[@") || (!selfName.isEmpty && selfName != "我" && preview.contains("@" + selfName))
    }
    /// Group previews read "name: text"; private ones have no sender.
    public static func sender(of preview: String) -> String? {
        let s = String(preview.utf16.dropFirst(countTagLength(preview))) ?? preview
        guard let r = s.range(of: ": ") ?? s.range(of: "：") else { return nil }
        let who = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        return who.isEmpty ? nil : who
    }
    public static func mayOpen(_ f: RowFacts, known: Set<String>, selfName: String) -> Bool {
        // Nothing unread: the owner has seen it all, even if the last message mentions them.
        guard f.badge || f.muted || countTagLength(f.preview) > 0 else { return true }
        if mentioned(f.preview, selfName: selfName) { return false }
        // A private message can start with "word: ", so the word must also be someone's name.
        guard let who = sender(of: f.preview), who != f.name else { return false }
        return known.contains(who)
    }
}
