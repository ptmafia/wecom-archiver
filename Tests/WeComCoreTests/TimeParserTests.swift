import Foundation
import Testing
@testable import WeComCore

// 2026-11-04 is a Wednesday.
private let now = makeDate("2026-11-04 12:00")

@Suite struct TimeParserTests {
    @Test func timeOnlyMeansToday() {
        #expect(TimeParser.parse("9:34", now: now) == "2026-11-04 09:34")
    }
    @Test func yesterday() {
        #expect(TimeParser.parse("昨日 14:46", now: now) == "2026-11-03 14:46")
    }
    @Test func weekdayMeansMostRecentPast() {
        #expect(TimeParser.parse("月曜日 17:54", now: now) == "2026-11-02 17:54")
        #expect(TimeParser.parse("金曜日 20:18", now: now) == "2026-10-30 20:18")
    }
    @Test func sameWeekdayAsTodayMeansAWeekAgo() {
        #expect(TimeParser.parse("水曜日 08:00", now: now) == "2026-10-28 08:00")
    }
    @Test func monthDayInCurrentYear() {
        #expect(TimeParser.parse("10月 19 15:16", now: now) == "2026-10-19 15:16")
    }
    @Test func monthDayInTheFutureMeansLastYear() {
        #expect(TimeParser.parse("12月 25 10:00", now: now) == "2025-12-25 10:00")
    }
    @Test func explicitYear() {
        #expect(TimeParser.parse("2025年 3月 5 9:01", now: now) == "2025-03-05 09:01")
        #expect(TimeParser.parse("2024年3月5日 09:01", now: now) == "2024-03-05 09:01")
    }
    @Test func olderYearsUseEnglishMonths() {
        #expect(TimeParser.parse("Sep 4, 2025 12:21", now: now) == "2025-09-04 12:21")
    }
    @Test func chineseForms() {
        #expect(TimeParser.parse("昨天 14:46", now: now) == "2026-11-03 14:46")
        #expect(TimeParser.parse("星期一 17:54", now: now) == "2026-11-02 17:54")
    }
    @Test func notATime() {
        #expect(TimeParser.parse("339K", now: now) == nil)
        #expect(TimeParser.parse("佐藤:", now: now) == nil)
        #expect(TimeParser.parse("24:99", now: now) == nil)
    }
}
