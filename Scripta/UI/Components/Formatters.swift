import Foundation

/// Display formatting for durations, timestamps and dates.
enum Formatters {
    /// "2:34" or "1:02:03".
    static func duration(_ seconds: TimeInterval) -> String {
        let value = Duration.seconds(max(0, seconds.rounded(.down)))
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond
        return value.formatted(.time(pattern: pattern))
    }

    /// Transcript timestamp, same format as `duration`.
    static func timestamp(_ seconds: TimeInterval) -> String {
        duration(seconds)
    }

    /// Wall-clock time of a moment in a recording, e.g. "15:26".
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Spoken duration for VoiceOver, e.g. "2 Minuten, 34 Sekunden".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.rounded(.down)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// Mail-style list date: time for today, "Gestern", otherwise the date.
    static func listDate(_ date: Date, relativeTo now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Gestern")
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    /// Localized language name for a BCP-47 code, e.g. "de" → "Deutsch".
    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
