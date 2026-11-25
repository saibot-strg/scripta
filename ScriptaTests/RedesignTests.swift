import Foundation
import Testing
@testable import Scripta

@MainActor
@Suite("Redesign: list headings, timeline lanes, settings panes")
struct RedesignTests {
    /// Monday-based weeks in UTC, independent of the machine's settings.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday, 25 November 2026, 14:00.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 14)) ?? .now
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: DateComponents(day: offset, hour: hour), to: start) ?? now
    }

    @Test("Newest first: today, yesterday, this week, then one heading per month")
    func headingsFollowTheDate() {
        let dates = [day(0), day(0, hour: 9), day(-1), day(-2), day(-10), day(-40)]
        let sections = DateSections.group(dates, by: { $0 }, now: now, calendar: calendar)
        #expect(sections.map(\.id) == ["today", "yesterday", "week", "2026-11", "2026-10"])
        #expect(sections.map(\.items.count) == [2, 1, 1, 1, 1])
    }

    @Test("Oldest first keeps the same headings in reverse")
    func headingsInAscendingOrder() {
        let dates = [day(-40), day(-10), day(-2), day(-1), day(0)]
        let sections = DateSections.group(dates, by: { $0 }, now: now, calendar: calendar)
        #expect(sections.map(\.id) == ["2026-10", "2026-11", "week", "yesterday", "today"])
    }

    @Test("Last week is not this week")
    func lastWeekGetsItsMonth() {
        // Sunday, 22 November: the week before the one that started on Monday the 23rd.
        #expect(DateSections.bucket(for: day(-3), now: now, calendar: calendar).id == "2026-11")
    }

    @Test("Rows under a heading show the time for today and yesterday, the day before that")
    func rowDates() {
        let today = Formatters.rowDate(day(0), relativeTo: now, calendar: calendar)
        let yesterday = Formatters.rowDate(day(-1), relativeTo: now, calendar: calendar)
        let older = Formatters.rowDate(day(-10), relativeTo: now, calendar: calendar)
        #expect(today == day(0).formatted(date: .omitted, time: .shortened))
        #expect(yesterday == day(-1).formatted(date: .omitted, time: .shortened))
        #expect(older != day(-10).formatted(date: .omitted, time: .shortened))
    }

    @Test("Lengths in rows: minutes, hours and minutes, seconds below a minute")
    func shortDurations() {
        #expect(Formatters.shortDuration(47 * 60 + 12).contains("47"))
        #expect(Formatters.shortDuration(42).contains("42"))
        let long = Formatters.shortDuration(92 * 60)
        #expect(long.contains("1") && long.contains("32"))
    }

    @Test("A voice's passages with short pauses become one turn on the timeline")
    func turnsMergeShortPauses() {
        let turns = SpeakerLanes.turns([
            (key: "a", start: 0, end: 4),
            (key: "a", start: 5, end: 8),      // 1 s pause: same turn
            (key: "b", start: 8.5, end: 10),
            (key: "a", start: 14, end: 15)     // 6 s later: a new turn
        ])
        #expect(turns.map(\.key) == ["a", "b"])
        #expect(turns[0].spans == [0...8, 14...15])
        #expect(turns[1].spans == [8.5...10])
    }

    @Test("A passage that ends before it starts doesn't break the timeline")
    func turnsTolerateBrokenTimes() {
        let turns = SpeakerLanes.turns([(key: 1, start: 5, end: 3)])
        #expect(turns[0].spans == [5...5])
    }

    @Test("The user's own lane comes first, others as they first speak")
    func lanesPutTheUserFirst() {
        let other = SpeakerLabel(role: .others)
        let me = SpeakerLabel(role: .me)
        let first = TranscriptSegment(index: 0, start: 0, end: 3, text: "Hallo")
        first.speaker = other
        let second = TranscriptSegment(index: 1, start: 3, end: 6, text: "Hi")
        second.speaker = me
        let lanes = SpeakerLanes.make(from: [first, second])
        #expect(lanes.map { $0.speaker?.role } == [.me, .others])
        #expect(lanes.map(\.spans) == [[3...6], [0...3]])
    }

    @Test("Turns are drawn inside the track, however short")
    func spanShapeStaysInBounds() {
        let shape = SpanShape(spans: [0...0.01, 99...100], duration: 100)
        let bounds = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 12)).boundingRect
        #expect(bounds.minX >= 0 && bounds.maxX <= 200.001)
        #expect(bounds.width > 190)
    }

    @Test("Settings: the merged panes still open by their old names")
    func mergedSettingsPanes() {
        #expect(SettingsView.Pane(name: "people") == .recognition)
        #expect(SettingsView.Pane(name: "languageModel") == .recognition)
        #expect(SettingsView.Pane(name: "transcription") == .recognition)
        #expect(SettingsView.Pane(name: "permissions") == .general)
        #expect(SettingsView.Pane(name: "dictation") == .dictation)
        #expect(SettingsView.Pane(name: "nope") == nil)
    }

    @Test("Every filter is reachable: a chip or the list menu")
    func filtersHaveAPlace() {
        let reachable = Set(LibraryFilterBar.chips + LibraryFilterBar.menuFilters)
        #expect(reachable == Set(LibraryFilter.allCases))
    }
}
