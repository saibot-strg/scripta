import Foundation

/// A run of list rows under one date heading ("Heute", "Gestern", …).
struct DateSection<Item> {
    let id: String
    let title: String
    var items: [Item]
}

/// Date headings for the recording list.
enum DateSections {
    /// Groups items that are already in date order into consecutive runs, so
    /// both sort directions keep their order.
    static func group<Item>(
        _ items: [Item],
        by date: (Item) -> Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DateSection<Item>] {
        var sections: [DateSection<Item>] = []
        for item in items {
            let bucket = bucket(for: date(item), now: now, calendar: calendar)
            if sections.last?.id == bucket.id {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(DateSection(id: bucket.id, title: bucket.title, items: [item]))
            }
        }
        return sections
    }

    /// Today, yesterday, the rest of this week, then one heading per month.
    static func bucket(for date: Date, now: Date, calendar: Calendar) -> (id: String, title: String) {
        if calendar.isDate(date, inSameDayAs: now) {
            return ("today", String(localized: "Heute"))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return ("yesterday", String(localized: "Gestern"))
        }
        if date < now, calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return ("week", String(localized: "Diese Woche"))
        }
        let parts = calendar.dateComponents([.year, .month], from: date)
        return ("\(parts.year ?? 0)-\(parts.month ?? 0)", date.formatted(.dateTime.month(.wide).year()))
    }
}
