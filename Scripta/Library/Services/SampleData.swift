#if DEBUG
import Foundation
import SwiftData

/// Dummy library content for previews and UI development (debug builds only).
/// The recordings have no audio files.
@MainActor
enum SampleData {
    static func insert(into context: ModelContext) {
        let now = Date.now
        func daysAgo(_ days: Double, hour: Int = 10) -> Date {
            let base = Calendar.current.date(bySettingHour: hour, minute: 15, second: 0, of: now) ?? now
            return base.addingTimeInterval(-days * 86_400)
        }

        let weekly = Recording(title: "Team-Weekly", createdAt: daysAgo(0, hour: 9), duration: 2_840,
                               source: .meeting, status: .done, languageCode: "de")
        context.insert(weekly)
        addMeetingTranscript(to: weekly)

        let memo = Recording(title: "Idee für den Vortrag", createdAt: daysAgo(1, hour: 18), duration: 154,
                             source: .microphone, status: .done, languageCode: "de")
        context.insert(memo)
        addTranscript(to: memo, language: "de", lines: [
            "Kurze Notiz für den Vortrag nächste Woche.",
            "Ich möchte mit einer Geschichte einsteigen, nicht mit Zahlen.",
            "Danach drei Beispiele aus dem Projekt, jeweils mit einer Folie.",
            "Am Ende eine klare Bitte an das Publikum.",
        ])

        let interview = Recording(title: "Podcast-Interview (EN)", createdAt: daysAgo(3, hour: 14), duration: 3_725,
                                  source: .importedFile, status: .done, languageCode: "en")
        context.insert(interview)
        addTranscript(to: interview, language: "en", lines: [
            "Welcome back to the show. Today we talk about on-device speech recognition.",
            "Thanks for having me. It is an exciting time for local models.",
            "What changed in the last two years?",
            "Mostly efficiency. Models like Parakeet run faster than real time on a laptop.",
        ])

        context.insert(Recording(title: "Kundentermin Müller GmbH", createdAt: daysAgo(4, hour: 11), duration: 1_980,
                                 source: .meeting, status: .notTranscribed))
        context.insert(Recording(title: "Vorlesung Kapitel 4", createdAt: daysAgo(6, hour: 8), duration: 5_410,
                                 source: .importedFile, status: .queued))

        let running = Recording(title: "Sprachnotiz Einkauf", createdAt: daysAgo(0, hour: 12), duration: 48,
                                source: .microphone, status: .running)
        running.transcriptionProgress = 0.42
        context.insert(running)

        let failed = Recording(title: "Telefonat mit Anna", createdAt: daysAgo(9, hour: 16), duration: 612,
                               source: .importedFile, status: .failed)
        failed.errorMessage = String(localized: "Die Audiodatei konnte nicht gelesen werden.")
        context.insert(failed)

        context.insert(Recording(title: "Gedanken zum Wochenende", createdAt: daysAgo(12, hour: 20), duration: 95,
                                 source: .microphone, status: .notTranscribed))
    }

    /// Plain transcript: one segment per line, evenly spaced.
    private static func addTranscript(to recording: Recording, language: String, lines: [String]) {
        let transcript = Transcript(languageCode: language, engineIdentifier: "sample")
        recording.transcript = transcript
        var start: TimeInterval = 0.4
        for (index, line) in lines.enumerated() {
            let end = start + Double(line.count) / 14
            transcript.segments.append(TranscriptSegment(index: index, start: start, end: end, text: line))
            start = end + 0.6
        }
        transcript.rebuildFullText()
    }

    /// Meeting transcript with "Ich" / "Andere" speaker labels.
    private static func addMeetingTranscript(to recording: Recording) {
        let transcript = Transcript(languageCode: "de", engineIdentifier: "sample")
        recording.transcript = transcript
        let me = SpeakerLabel(role: .me)
        let others = SpeakerLabel(role: .others)
        transcript.speakers.append(contentsOf: [me, others])

        let turns: [(SpeakerLabel, String)] = [
            (others, "Guten Morgen zusammen! Können mich alle hören?"),
            (me, "Ja, laut und deutlich. Guten Morgen!"),
            (others, "Super. Dann starten wir mit dem Stand zum Release."),
            (me, "Die Aufnahme-Funktion ist fertig, die Tests laufen. Offen ist noch der Export als SRT."),
            (others, "Wie lange brauchst du dafür ungefähr?"),
            (me, "Ich denke, bis Donnerstag ist das erledigt."),
            (others, "Passt. Dann sprechen wir als Nächstes über die Einstellungen."),
        ]
        var start: TimeInterval = 1.2
        for (index, turn) in turns.enumerated() {
            let end = start + Double(turn.1.count) / 13
            let segment = TranscriptSegment(index: index, start: start, end: end, text: turn.1)
            transcript.segments.append(segment)
            segment.speaker = turn.0
            start = end + 0.8
        }
        transcript.rebuildFullText()
    }
}
#endif
