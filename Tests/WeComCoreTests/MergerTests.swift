import Foundation
import Testing
@testable import WeComCore

private func m(_ text: String, _ sender: String = "佐藤") -> Message {
    Message(at: "2026-11-04 09:00", sender: sender, kind: .text, text: text)
}
private func pic(_ sender: String = "店長") -> Message { Message(at: nil, sender: sender, kind: .image, text: "") }
private func texts(_ r: MergeResult) -> [String] { r.merged.map { $0.kind == .gap ? "|" : $0.text } }

@Suite struct MergerTests {
    @Test func emptyArchiveTakesEverything() {
        let r = Merger.combine(existing: [], fresh: [m("a"), m("b")])
        #expect(texts(r) == ["a", "b"] && r.added == 2)
    }
    @Test func appendsOnlyNewMessages() {
        let r = Merger.combine(existing: [m("a"), m("b"), m("c"), m("d")], fresh: [m("b"), m("c"), m("d"), m("e")])
        #expect(texts(r) == ["a", "b", "c", "d", "e"] && r.added == 1)
    }
    @Test func nothingNew() {
        let r = Merger.combine(existing: [m("a"), m("b"), m("c")], fresh: [m("b"), m("c")])
        #expect(texts(r) == ["a", "b", "c"] && r.added == 0)
    }
    @Test func repeatedPicturesDoNotSwallowWhatIsBetween() {
        // Four pictures, a reply, four more pictures: lining up on the last four alone would lose the reply.
        let old = [m("早"), pic(), pic(), pic(), pic()]
        let fresh = [m("早"), pic(), pic(), pic(), pic(), m("收到", "本部"), pic(), pic(), pic(), pic()]
        #expect(texts(Merger.combine(existing: old, fresh: fresh)) == ["早", "", "", "", "", "收到", "", "", "", ""])
    }
    @Test func picturesAloneAreNeverEnoughToLineUp() {
        let old = [m("早"), pic(), pic(), pic(), pic()]
        let fresh = [pic(), pic(), pic(), pic(), m("收到", "本部"), pic(), pic(), pic(), pic()]
        let r = Merger.combine(existing: old, fresh: fresh)
        #expect(r.gaps == 1 && r.merged.count == old.count + 1 + fresh.count)
    }
    @Test func aReadThatLinesUpWithNothingIsKeptBehindAGap() {
        let r = Merger.combine(existing: [m("a"), m("b"), m("c")], fresh: [m("x"), m("y"), m("z")])
        #expect(texts(r) == ["a", "b", "c", "|", "x", "y", "z"] && r.gaps == 1 && r.added == 3)
    }
    @Test func anOlderReadGoesInFront() {
        let r = Merger.combine(existing: [m("x"), m("y")], fresh: [m("a"), m("b")], position: .oldest)
        #expect(texts(r) == ["a", "b", "|", "x", "y"])
    }
    @Test func aDeeperReadClosesTheGap() {
        let gapped = Merger.combine(existing: [m("a"), m("b"), m("c")], fresh: [m("x"), m("y"), m("z")]).merged
        let r = Merger.combine(existing: gapped, fresh: [m("a"), m("b"), m("c"), m("p"), m("q"), m("x"), m("y"), m("z")])
        #expect(texts(r) == ["a", "b", "c", "p", "q", "x", "y", "z"] && r.gaps == 0 && r.added == 2)
    }
    @Test func anOlderStretchLinesUpWithTheHead() {
        let r = Merger.combine(existing: [m("c"), m("d"), m("e")], fresh: [m("a"), m("b"), m("c"), m("d"), m("e")], position: .oldest)
        #expect(texts(r) == ["a", "b", "c", "d", "e"])
    }
    @Test func aRecalledMessageDoesNotBreakALongOverlap() {
        let old = (1...20).map { m("t\($0)") }
        var fresh = (11...25).map { m("t\($0)") }
        fresh[5] = Message(at: nil, sender: "系统消息", kind: .system, text: "撤回")
        let r = Merger.combine(existing: old, fresh: fresh)
        #expect(r.gaps == 0 && r.merged.count == 25 && r.merged[15].text == "撤回")
    }
    @Test func aShorterReadNeverShrinksTheArchive() {
        let r = Merger.combine(existing: [m("a"), m("b"), m("c"), m("d"), m("e")], fresh: [m("c"), m("d"), m("e"), m("f")])
        #expect(texts(r) == ["a", "b", "c", "d", "e", "f"])
    }
    @Test func aReadThatHasMoreButReachesLessFarBackKeepsTheOldPart() {
        // The old reconcile swapped in any read that was at least as long.
        let existing = [m("a"), m("b"), m("c"), m("d")]
        let r = Merger.combine(existing: existing, fresh: [m("b"), m("c"), m("d"), m("e"), m("f"), m("g")])
        #expect(texts(r) == ["a", "b", "c", "d", "e", "f", "g"])
    }
    @Test func senderIsPartOfIdentity() {
        let r = Merger.combine(existing: [m("ok", "佐藤"), m("x")], fresh: [m("ok", "田中"), m("y")])
        #expect(r.gaps == 1)
    }
    @Test func aCompleteReadReplacesStretchesItCannotPlace() {
        let broken = Merger.combine(existing: [m("a"), m("b"), m("c")], fresh: [m("q"), m("r"), m("s")]).merged
        let r = Merger.combine(existing: broken, fresh: [m("a"), m("b"), m("c"), m("d")], complete: true)
        #expect(texts(r) == ["a", "b", "c", "d"] && r.dropped.map(\.text) == ["q", "r", "s"])
    }
    @Test func aCompleteReadKeepsEverythingItLinesUpWith() {
        let r = Merger.combine(existing: [m("a"), m("b"), m("c")], fresh: [m("a"), m("b"), m("c"), m("d")], complete: true)
        #expect(texts(r) == ["a", "b", "c", "d"] && r.dropped.isEmpty)
    }
    @Test func twoMessagesInCommonAreNotEnough() {
        let r = Merger.combine(existing: [m("x"), m("好的"), m("收到")], fresh: [m("好的"), m("收到"), m("新")])
        #expect(r.gaps == 1 && r.added == 3)
    }
    @Test func ambiguousPlacementIsNotGuessed() {
        // The fresh run fits twice in the archive; neither place is taken.
        let r = Merger.combine(existing: [m("a"), m("b"), m("c"), m("a"), m("b"), m("c")], fresh: [m("a"), m("b"), m("c")])
        #expect(r.added == 3 && r.gaps == 1)
    }
}

@Suite struct FillTimesTests {
    @Test func missingTimesInheritThePreviousOne() {
        let a = Message(at: "2026-11-04 09:00", sender: "佐藤", kind: .text, text: "a")
        let b = Message(at: nil, sender: "佐藤", kind: .text, text: "b")
        #expect(Merger.fillTimes([a, b]).last?.at == "2026-11-04 09:00")
    }
    @Test func gapMarkersKeepNoTime() {
        let a = Message(at: "2026-11-04 09:00", sender: "佐藤", kind: .text, text: "a")
        #expect(Merger.fillTimes([a, Merger.gap]).last?.at == nil)
    }
}

@Suite struct StateTests {
    @Test func stateSavedBeforeReachExistedStillLoads() throws {
        let old = #"{"signature":"s","complete":true,"attempts":2,"count":9,"lastRead":"x","depth":3}"#
        let st = try JSONDecoder().decode(ConvState.self, from: Data(old.utf8))
        #expect(st.reach == 0 && st.count == 9 && st.complete && st.retryAfter == nil)
    }
    @Test func anUnreadableStateFileIsNotTreatedAsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = Archive(root: root)
        try a.prepare()
        #expect(a.loadState() == [:])
        try Data("{broken".utf8).write(to: a.statePath)
        #expect(a.loadState() == nil)
    }
    @Test func dailyBackupKeepsAWeek() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = Archive(root: root)
        try a.prepare()
        try a.save("群", [m("a")])
        for day in 1...9 { a.backUpDaily(now: makeDate(String(format: "2026-11-%02d 10:00", day))) }
        let kept = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backup").path).sorted()
        #expect(kept.count == 7 && kept.last == "2026-11-09")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("backup/2026-11-09/archive/群.jsonl").path))
    }
}

@Suite struct GroupMembersTests {
    @Test func privateChatsDoNotCount() {
        let priv = [m("hi", "张伟"), m("yo", "李明"), Message(at: nil, sender: "系统消息", kind: .system, text: "x")]
        let group = [m("a", "佐藤"), m("b", "田中"), m("c", "李明")]
        let g = GroupMembers.from([("张伟", priv), ("群", group)], selfName: "李明")
        #expect(g == ["佐藤", "田中"])
    }
}

@Suite struct ChatSearchTests {
    @Test func everyWordMustAppear() {
        #expect(ChatSearch.matches("新店の什器を確認", ["什器", "確認"]))
        #expect(!ChatSearch.matches("新店の什器を確認", ["什器", "搬入"]))
        #expect(!ChatSearch.matches("新店", []))
    }
    @Test func ignoresCase() {
        #expect(ChatSearch.matches("POS の件", ["pos"]))
    }
    @Test func hidesPhonesAndEmails() {
        let got = ChatSearch.mask("電話 090-1234-5678 と a.b@example.com、03-1234-5678、13812345678 まで")
        #expect(!got.contains("5678") && !got.contains("example.com") && !got.contains("13812345678"))
    }
    @Test func leavesDatesAndPricesAlone() {
        #expect(ChatSearch.mask("2026-11-04 に 1,200 円") == "2026-11-04 に 1,200 円")
    }
    @Test func excerptShowsTheMatch() {
        let text = String(repeating: "あ", count: 300) + "什器" + String(repeating: "い", count: 300)
        let got = ChatSearch.excerpt(text, around: "什器")
        #expect(got.contains("什器") && got.count <= 82)
    }
    @Test func newestFirstAndOnlyText() {
        let a = Message(at: "2026-11-01 09:00", sender: "佐藤", kind: .text, text: "什器 a")
        let b = Message(at: "2026-11-03 09:00", sender: "鈴木", kind: .text, text: "什器 b")
        let c = Message(at: "2026-11-04 09:00", sender: "", kind: .system, text: "什器 c")
        let got = ChatSearch.find(["什器"], in: [(conv: "群", messages: [a, b, c])])
        #expect(got.map(\.sender) == ["鈴木", "佐藤"])
    }
}

@Suite struct ConversationListTests {
    @Test func foldersAndFeatureEntriesAreNotChats() {
        for n in ["最小限のチャット", "已最小化的聊天", "Minimized Chats", "カレンダー", "メールボックス", "WeDrive"] {
            #expect(!ConversationList.isChat(n), "\(n)")
        }
    }
    @Test func aGroupThatOnlyMentionsAFeatureIsAChat() {
        #expect(ConversationList.isChat("店舗運営"))
        #expect(ConversationList.isChat("カレンダー共有グループ"))
    }
}
