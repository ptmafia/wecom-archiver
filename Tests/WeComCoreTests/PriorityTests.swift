import Foundation
import Testing
@testable import WeComCore

private let now = makeDate("2026-11-06 12:00")
private func say(_ sender: String, _ text: String = "内容", at: String = "2026-11-05 10:00", kind: Kind = .text) -> Message {
    Message(at: at, sender: sender, kind: kind, text: text)
}

@Suite struct PriorityTests {
    @Test func aChatTheOwnerTakesPartInIsHigh() {
        let ms = (0..<20).map { say($0 % 2 == 0 ? "李明" : "张伟") }
        #expect(Priority.tier(Priority.score(ms, selfName: "李明", now: now)) == .high)
    }
    @Test func aNotificationNobodyAnswersIsLow() {
        let ms = (0..<30).map { _ in say("通知机器人", "日报已生成") }
        #expect(Priority.tier(Priority.score(ms, selfName: "李明", now: now)) == .low)
    }
    @Test func aBigGroupTheOwnerNeverSpeaksInIsLow() {
        let ms = (0..<60).map { say("成员\($0 % 40)") }
        #expect(Priority.tier(Priority.score(ms, selfName: "李明", now: now)) == .low)
    }
    @Test func beingMentionedLiftsAGroup() {
        let quiet = (0..<60).map { say("成员\($0 % 8)") }
        let mentioned = quiet + (0..<5).map { _ in say("成员1", "@李明 请确认") }
        #expect(Priority.score(mentioned, selfName: "李明", now: now) > Priority.score(quiet, selfName: "李明", now: now))
        #expect(Priority.tier(Priority.score(mentioned, selfName: "李明", now: now)) != .low)
    }
    @Test func wordsTheOwnerCaresAboutLiftAConversation() {
        let plain = (0..<30).map { say("成员\($0 % 5)", "今天的安排") } + [say("李明")]
        let store = (0..<30).map { say("成员\($0 % 5)", "青葉店的什器") } + [say("李明")]
        #expect(Priority.score(store, selfName: "李明", words: ["青葉"], now: now) > Priority.score(plain, selfName: "李明", words: ["青葉"], now: now))
    }
    @Test func aGroupNamedAfterSomethingTheOwnerCaresAboutIsNotLow() {
        // A store's group the owner only reads: the name alone says it matters.
        let ms = (0..<60).map { say("成员\($0 % 30)") }
        #expect(Priority.tier(Priority.score(ms, selfName: "李明", words: ["青葉"], name: "新店準備室【青葉】", now: now)) != .low)
        #expect(Priority.tier(Priority.score(ms, selfName: "李明", words: ["青葉"], name: "雑談", now: now)) == .low)
    }
    @Test func anOldQuietConversationScoresLessThanARecentOne() {
        let old = (0..<20).map { say($0 % 2 == 0 ? "李明" : "张伟", at: "2025-01-05 10:00") }
        let recent = (0..<20).map { say($0 % 2 == 0 ? "李明" : "张伟") }
        #expect(Priority.score(recent, selfName: "李明", now: now) > Priority.score(old, selfName: "李明", now: now))
    }
    @Test func emptyScoresZero() {
        #expect(Priority.score([], selfName: "李明", now: now) == 0)
    }
    @Test func unreadConversationsAreGuessedFromTheListRow() {
        let privateChat = Priority.estimate(name: "张伟", sender: nil, selfName: "李明", known: [])
        let ownGroup = Priority.estimate(name: "项目群", sender: "李明", selfName: "李明", known: [])
        let colleagues = Priority.estimate(name: "项目群", sender: "张伟", selfName: "李明", known: ["张伟"])
        let stranger = Priority.estimate(name: "广告群", sender: "某人", selfName: "李明", known: [])
        let store = Priority.estimate(name: "新店準備室【青葉】", sender: "某人", selfName: "李明", known: [], words: ["青葉"])
        #expect(privateChat > colleagues && ownGroup > colleagues && colleagues > stranger && store > stranger)
    }
}

@Suite struct StageTests {
    @Test func justInstalled() {
        #expect(Stage.of(total: 400, neverRead: 300, historyLeft: 400) == .start)
    }
    @Test func catchingUpOnHistory() {
        #expect(Stage.of(total: 400, neverRead: 5, historyLeft: 120) == .history)
    }
    @Test func dayToDay() {
        #expect(Stage.of(total: 400, neverRead: 2, historyLeft: 0) == .daily)
    }
    @Test func aFewNewContactsDoNotSendItBackToTheStart() {
        #expect(Stage.of(total: 400, neverRead: 8, historyLeft: 0) == .daily)
    }
}
