import Foundation
import Testing
@testable import Scripta

@Suite("Formatters")
struct FormattersTests {
    @Test("Durations use m:ss below an hour and h:mm:ss above", arguments: [
        (0.0, "0:00"),
        (9.9, "0:09"),
        (154, "2:34"),
        (3_599, "59:59"),
        (3_600, "1:00:00"),
        (5_410, "1:30:10"),
        (-5, "0:00"),
    ])
    func duration(seconds: TimeInterval, expected: String) {
        #expect(Formatters.duration(seconds) == expected)
    }

    @Test("List dates: time today, 'yesterday', otherwise a date")
    func listDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15)))
        let earlierToday = now.addingTimeInterval(-3_600)
        let yesterday = now.addingTimeInterval(-86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)

        #expect(Formatters.listDate(earlierToday, relativeTo: now, calendar: calendar)
            == earlierToday.formatted(date: .omitted, time: .shortened))
        #expect(Formatters.listDate(yesterday, relativeTo: now, calendar: calendar) == String(localized: "Gestern"))
        #expect(Formatters.listDate(lastWeek, relativeTo: now, calendar: calendar)
            == lastWeek.formatted(date: .numeric, time: .omitted))
    }
}
