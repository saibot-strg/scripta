import Foundation
import Testing
@testable import Scripta

@Suite("Transcript export")
struct ExportTests {
    private func words(_ text: String, start: TimeInterval, step: TimeInterval = 0.4) -> [Scripta.WordTiming] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + Double(index) * step
            return Scripta.WordTiming(text: String(word), start: begin, end: begin + step * 0.8, confidence: 0.91234)
        }
    }

    private func document(meeting: Bool) -> TranscriptDocument {
        TranscriptDocument(
            title: "Team-Weekly",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            duration: 3_725,
            languageCode: "de",
            engine: "parakeet-tdt-0.6b-v3",
            segments: [
                .init(start: 1.2, end: 3.0, text: "Guten Morgen zusammen!", speaker: meeting ? "Andere" : nil,
                      words: words("Guten Morgen zusammen!", start: 1.2)),
                .init(start: 3_661.5, end: 3_663.25, text: "Bis Donnerstag.", speaker: meeting ? "Ich" : nil,
                      words: words("Bis Donnerstag.", start: 3_661.5)),
            ]
        )
    }

    @Test("Subtitle timestamps use hours, minutes, seconds and milliseconds")
    func subtitleTime() {
        #expect(TranscriptExporter.subtitleTime(0, separator: ",") == "00:00:00,000")
        #expect(TranscriptExporter.subtitleTime(3_661.5, separator: ",") == "01:01:01,500")
        #expect(TranscriptExporter.subtitleTime(59.9996, separator: ".") == "00:01:00.000")
    }

    @Test("SRT: numbered cues with speaker prefix")
    func srt() {
        let srt = TranscriptExporter.srt(document(meeting: true))
        #expect(srt.hasPrefix("1\n00:00:01,200 --> 00:00:02,320\nAndere: Guten Morgen zusammen!\n"))
        #expect(srt.contains("\n2\n01:01:01,500 --> 01:01:02,220\nIch: Bis Donnerstag.\n"))
    }

    @Test("WebVTT: header and voice tags")
    func vtt() {
        let vtt = TranscriptExporter.vtt(document(meeting: true))
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:01.200 --> "))
        #expect(vtt.contains("<v Andere>Guten Morgen zusammen!"))
        #expect(!TranscriptExporter.vtt(document(meeting: false)).contains("<v "))
    }

    @Test("Long segments are split into readable subtitles of at most two lines")
    func cueSplitting() {
        let sentence = Array(repeating: "Wort", count: 60).joined(separator: " ")
        let long = TranscriptDocument(
            title: "Lang", createdAt: .now, duration: 30, languageCode: nil, engine: "test",
            segments: [.init(start: 0, end: 24, text: sentence, speaker: nil, words: words(sentence, start: 0))]
        )
        let cues = TranscriptExporter.cues(long)
        #expect(cues.count > 2)
        #expect(cues.allSatisfy { $0.text.count <= 84 && $0.end - $0.start <= 7.01 })
        #expect(cues.map(\.text).joined(separator: " ") == sentence)

        let srt = TranscriptExporter.srt(long)
        let textLines = srt.split(separator: "\n").filter { !$0.contains("-->") && Int($0) == nil }
        #expect(textLines.allSatisfy { $0.count <= 45 })
    }

    @Test("Edited segments without word timings become one cue")
    func editedSegment() {
        let edited = TranscriptDocument(
            title: "x", createdAt: .now, duration: 5, languageCode: nil, engine: "test",
            segments: [.init(start: 1, end: 4, text: "Korrigierter Text.", speaker: nil, words: [])]
        )
        #expect(TranscriptExporter.cues(edited) == [.init(start: 1, end: 4, text: "Korrigierter Text.", speaker: nil)])
    }

    @Test("Plain text: timestamps and speakers; header optional")
    func plainText() {
        let body = TranscriptExporter.plainText(document(meeting: true), includeHeader: false)
        #expect(body == "[0:01] Andere: Guten Morgen zusammen!\n[1:01:01] Ich: Bis Donnerstag.\n")
        let full = TranscriptExporter.plainText(document(meeting: false), includeHeader: true)
        #expect(full.hasPrefix("Team-Weekly\n"))
        #expect(full.contains("1:02:05"))
        #expect(full.contains("[0:01] Guten Morgen zusammen!"))
    }

    @Test("Markdown: title, details and speaker names")
    func markdown() {
        let markdown = TranscriptExporter.markdown(document(meeting: true))
        #expect(markdown.hasPrefix("# Team-Weekly\n"))
        #expect(markdown.contains("**Andere** `0:01`  \nGuten Morgen zusammen!"))
        #expect(markdown.contains("**Ich** `1:01:01`"))
    }

    @Test("JSON: segments with speakers and word timings, rounded to milliseconds")
    func json() throws {
        let data = try TranscriptExporter.json(document(meeting: true))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["title"] as? String == "Team-Weekly")
        #expect(object["language"] as? String == "de")
        let segments = try #require(object["segments"] as? [[String: Any]])
        #expect(segments.count == 2)
        #expect(segments[0]["speaker"] as? String == "Andere")
        let firstWord = try #require((segments[0]["words"] as? [[String: Any]])?.first)
        #expect(firstWord["text"] as? String == "Guten")
        #expect(firstWord["confidence"] as? Double == 0.912)
        #expect((object["createdAt"] as? String)?.hasPrefix("2025-") == true)
    }

    @Test("All formats produce data")
    func allFormats() throws {
        for format in ExportFormat.allCases {
            #expect(try !TranscriptExporter.data(document(meeting: true), as: format).isEmpty, "\(format)")
        }
    }

    @Test("Titles become safe file names")
    func fileNames() {
        #expect(AppModel.fileName(for: "Meeting 18.10.2026, 11:57") == "Meeting 18.10.2026, 11-57")
        #expect(AppModel.fileName(for: "a/b\\c") == "a-b-c")
        #expect(!AppModel.fileName(for: "   ").isEmpty)
    }
}
