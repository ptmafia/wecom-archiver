import Foundation
import Testing
@testable import WeComCore

@Suite struct ScheduleTests {
    let now = makeDate("2026-11-04 14:00")
    @Test func readsAfterWeComHasBeenLeftAlone() {
        #expect(Schedule.mayRead(locked: false, wecomInFront: false, lastInFront: now.addingTimeInterval(-61), now: now))
    }
    @Test func waitsRightAfterLeavingWeCom() {
        #expect(!Schedule.mayRead(locked: false, wecomInFront: false, lastInFront: now.addingTimeInterval(-30), now: now))
    }
    @Test func neverReadsWhileWeComIsInFront() {
        #expect(!Schedule.mayRead(locked: false, wecomInFront: true, lastInFront: .distantPast, now: now))
    }
    @Test func neverReadsWhileLocked() {
        #expect(!Schedule.mayRead(locked: true, wecomInFront: false, lastInFront: .distantPast, now: now))
    }
}
