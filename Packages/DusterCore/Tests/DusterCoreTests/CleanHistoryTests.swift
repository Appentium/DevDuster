import Foundation
import Testing
@testable import DusterCore

@Suite struct CleanHistoryTests {
    @Test func readsRecordsAndSkipsBrokenLines() throws {
        let fixture = try Fixture()
        let log = CleanLog(home: fixture.home)
        try log.append(mode: .trash, bytes: 1_000, path: "/a")
        try log.append(mode: .delete, bytes: 2_500, path: "/b\twith tab")
        let handle = try FileHandle(forWritingTo: log.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage\nnot-a-date\ttrash\t5\t/c\n".utf8))
        try handle.close()

        let history = CleanHistory(logs: [log, CleanLog(url: fixture.url("missing.log"))])
        #expect(history.records.map(\.bytes) == [1_000, 2_500])
        #expect(history.totalBytes == 3_500)
        #expect(history.lastCleaned != nil)
    }

    @Test func totalsSinceAndByWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        let now = try Date("2026-11-25T12:00:00Z", strategy: .iso8601)
        let history = CleanHistory(records: [
            CleanRecord(date: try Date("2026-11-24T08:00:00Z", strategy: .iso8601), bytes: 100),
            CleanRecord(date: try Date("2026-11-23T00:00:00Z", strategy: .iso8601), bytes: 50),
            CleanRecord(date: try Date("2026-11-22T23:59:59Z", strategy: .iso8601), bytes: 20),
            CleanRecord(date: try Date("2026-10-01T00:00:00Z", strategy: .iso8601), bytes: 7),
        ])

        #expect(history.bytes(since: try Date("2026-11-23T00:00:00Z", strategy: .iso8601)) == 150)
        let weeks = history.weeklyTotals(weeks: 3, now: now, calendar: calendar)
        #expect(weeks.map(\.bytes) == [0, 20, 150])
        #expect(weeks.last?.weekStart == (try Date("2026-11-23T00:00:00Z", strategy: .iso8601)))
        #expect(history.weeklyTotals(weeks: 0, now: now, calendar: calendar).isEmpty)
        #expect(CleanHistory(records: []).lastCleaned == nil)
    }
}
