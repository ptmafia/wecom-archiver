import Testing
@testable import WeComCore

@Suite struct UnreadRuleTests {
    let known: Set<String> = ["张伟", "王芳", "Emma Brown"]
    func facts(_ name: String, _ preview: String, badge: Bool = false, muted: Bool = false) -> RowFacts {
        RowFacts(name: name, preview: preview, badge: badge, muted: muted)
    }
    func open(_ f: RowFacts) -> Bool { UnreadRule.mayOpen(f, known: known, selfName: "李明") }

    @Test func readConversationsOpen() {
        #expect(open(facts("山田花子", "お疲れ様！")))
        #expect(open(facts("企画チーム", "王芳: 好的")))
    }
    @Test func unreadPrivateChatStaysClosed() {
        #expect(!open(facts("山田花子", "お疲れ様！", badge: true)))
    }
    @Test func unreadGroupOpens() {
        #expect(open(facts("企画チーム", "Emma Brown: お疲れ様です", badge: true)))
        #expect(open(facts("采购群", "[2 メッセージ ] 王芳: @刘洋 好的", muted: true)))
    }
    @Test func mentionKeepsAGroupClosedEvenWithoutABadge() {
        #expect(!open(facts("企画チーム", "[あなたが言及されました] 王芳: 看下", badge: true)))
        #expect(!open(facts("企画チーム", "[@全員] 王芳: 看下", muted: true)))
        #expect(!open(facts("企画チーム", "[2 メッセージ ] [@全員] 王芳: 看下")))
        #expect(!open(facts("企画チーム", "[有人@我] 王芳: 看下", badge: true)))
    }
    @Test func nameInTheTextCountsAsAMention() {
        #expect(!open(facts("企画チーム", "王芳: @李明 看下", badge: true)))
    }
    @Test func aMentionTheOwnerHasAlreadyReadDoesNotHoldTheGroup() {
        #expect(open(facts("企画チーム", "王芳: @李明 看下")))
    }
    @Test func someoneElsesMentionDoesNotCount() {
        #expect(open(facts("企画チーム", "王芳: @刘洋 看下", badge: true)))
    }
    @Test func aColonInAPrivateMessageIsNotASender() {
        #expect(!open(facts("山田花子", "结论: 可以", badge: true)))
    }
    @Test func unknownSenderStaysClosedUntilProvenAGroup() {
        #expect(!open(facts("某群", "陌生人: 你好", badge: true)))
    }
    @Test func mutedRowWithoutProofStaysClosedBecauseItsDotIsInvisible() {
        #expect(!open(facts("山田花子", "好的", muted: true)))
    }
    @Test func countTagAloneMeansUnread() {
        #expect(!open(facts("某人", "[3 メッセージ ] 你好")))
    }
    @Test func senderIsReadPastTheCountTag() {
        #expect(UnreadRule.sender(of: "[44 メッセージ ] 王芳: 好") == "王芳")
        #expect(UnreadRule.sender(of: "好的") == nil)
    }
}

@Suite struct OtherLanguagesTests {
    let known: Set<String> = ["张伟"]
    func open(_ p: String, badge: Bool = true) -> Bool {
        UnreadRule.mayOpen(RowFacts(name: "群", preview: p, badge: badge, muted: false), known: known, selfName: "李明")
    }
    @Test func mentionTagsInEveryLanguage() {
        for tag in ["[有人@我]", "[You were mentioned]", "[@所有人]", "[@All]"] { #expect(!open("\(tag) 张伟: 看下")) }
    }
    @Test func countTagsInEveryLanguage() {
        #expect(UnreadRule.sender(of: "[3条] 张伟: 好") == "张伟")
        #expect(UnreadRule.sender(of: "[12 messages] 张伟: ok") == "张伟")
        #expect(!open("[3条] 你好", badge: false))
    }
    @Test func fullWidthColon() {
        #expect(UnreadRule.sender(of: "张伟：好的") == "张伟")
    }
}

@Suite struct TimeParserLanguagesTests {
    let now = makeDate("2026-11-05 14:00")   // a Thursday
    @Test func english() {
        #expect(TimeParser.parse("Today 09:30", now: now) == "2026-11-05 09:30")
        #expect(TimeParser.parse("Yesterday 23:10", now: now) == "2026-11-04 23:10")
        #expect(TimeParser.parse("Monday 08:00", now: now) == "2026-11-02 08:00")
        #expect(TimeParser.parse("Nov 3 12:21", now: now) == "2026-11-03 12:21")
        #expect(TimeParser.parse("Dec 30 12:21", now: now) == "2025-12-30 12:21")
    }
    @Test func twelveHourClock() {
        #expect(TimeParser.parse("3:20 PM", now: now) == "2026-11-05 15:20")
        #expect(TimeParser.parse("12:05 AM", now: now) == "2026-11-05 00:05")
        #expect(TimeParser.parse("昨日 午後 3:20", now: now) == "2026-11-04 15:20")
        #expect(TimeParser.parse("下午3:20", now: now) == "2026-11-05 15:20")
        #expect(TimeParser.parse("上午11:59", now: now) == "2026-11-05 11:59")
    }
    @Test func chineseWeekdays() {
        #expect(TimeParser.parse("周一 08:00", now: now) == "2026-11-02 08:00")
        #expect(TimeParser.parse("2026/10/01 08:00", now: now) == "2026-10-01 08:00")
    }
}
