import Foundation
import UniformTypeIdentifiers

/// A transcript as plain values, detached from SwiftData, so exporting can
/// run anywhere and is easy to test.
struct TranscriptDocument: Sendable, Equatable {
    struct Segment: Sendable, Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var speaker: String?
        var words: [WordTiming]
    }

    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var languageCode: String?
    var engine: String
    var segments: [Segment]

    var hasSpeakers: Bool { Set(segments.compactMap(\.speaker)).count > 1 }
}

extension TranscriptDocument {
    @MainActor
    init(recording: Recording, transcript: Transcript) {
        let showsSpeakers = transcript.hasSpeakers
        self.init(
            title: recording.title,
            createdAt: recording.createdAt,
            duration: recording.duration,
            languageCode: transcript.languageCode,
            engine: transcript.engineIdentifier,
            segments: transcript.orderedSegments.map { segment in
                Segment(
                    start: segment.start,
                    end: segment.end,
                    text: segment.text,
                    speaker: showsSpeakers ? segment.speaker?.displayName : nil,
                    // After a manual correction the word timings no longer match the text.
                    words: segment.isEdited ? [] : segment.words
                )
            }
        )
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case text
    case markdown
    case srt
    case vtt
    case json

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .text: "txt"
        case .markdown: "md"
        case .srt: "srt"
        case .vtt: "vtt"
        case .json: "json"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .text: "Text (.txt)"
        case .markdown: "Markdown (.md)"
        case .srt: "Untertitel SRT (.srt)"
        case .vtt: "Untertitel WebVTT (.vtt)"
        case .json: "JSON mit Zeitstempeln (.json)"
        }
    }

    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .markdown: UTType("net.daringfireball.markdown") ?? .plainText
        case .srt: UTType(filenameExtension: "srt") ?? .plainText
        case .vtt: UTType(filenameExtension: "vtt") ?? .plainText
        case .json: .json
        }
    }
}

/// Renders transcripts in the export formats.
enum TranscriptExporter {
    static func data(_ document: TranscriptDocument, as format: ExportFormat) throws -> Data {
        switch format {
        case .text: Data(plainText(document, includeHeader: true).utf8)
        case .markdown: Data(markdown(document).utf8)
        case .srt: Data(srt(document).utf8)
        case .vtt: Data(vtt(document).utf8)
        case .json: try json(document)
        }
    }

    // MARK: - Text

    /// Readable text: one paragraph per segment, with timestamps and speakers.
    /// Without the header this is what "Transkript kopieren" puts on the clipboard.
    static func plainText(_ document: TranscriptDocument, includeHeader: Bool) -> String {
        var lines: [String] = []
        if includeHeader {
            lines.append(document.title)
            lines.append(headerDetails(document).joined(separator: " · "))
            lines.append("")
        }
        for segment in document.segments {
            var line = "[\(Formatters.timestamp(segment.start))] "
            if let speaker = segment.speaker { line += "\(speaker): " }
            lines.append(line + segment.text)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func markdown(_ document: TranscriptDocument) -> String {
        var lines = ["# \(document.title)", ""]
        lines += headerDetails(document).map { "- \($0)" }
        lines += ["", "---", ""]
        var previousSpeaker: String?
        for segment in document.segments {
            let time = "`\(Formatters.timestamp(segment.start))`"
            if let speaker = segment.speaker, speaker != previousSpeaker {
                lines.append("**\(speaker)** \(time)  ")
                lines.append(segment.text)
            } else {
                lines.append("\(time) \(segment.text)")
            }
            lines.append("")
            previousSpeaker = segment.speaker
        }
        return lines.joined(separator: "\n")
    }

    private static func headerDetails(_ document: TranscriptDocument) -> [String] {
        var details = [
            document.createdAt.formatted(date: .long, time: .shortened),
            Formatters.duration(document.duration),
        ]
        if let code = document.languageCode {
            details.append(Formatters.languageName(code))
        }
        return details
    }

    // MARK: - Subtitles

    struct Cue: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var speaker: String?
    }

    /// Subtitle-sized cues: at most `maxDuration` seconds and `maxCharacters`
    /// characters (two lines). Long segments are split at word boundaries using
    /// the word timings.
    static func cues(
        _ document: TranscriptDocument,
        maxDuration: TimeInterval = 7,
        maxCharacters: Int = 84
    ) -> [Cue] {
        var cues: [Cue] = []
        for segment in document.segments {
            guard !segment.words.isEmpty else {
                cues.append(Cue(start: segment.start, end: segment.end, text: segment.text, speaker: segment.speaker))
                continue
            }
            var current: [WordTiming] = []
            func flush() {
                guard let first = current.first, let last = current.last else { return }
                cues.append(Cue(start: first.start, end: last.end, text: current.map(\.text).joined(separator: " "), speaker: segment.speaker))
                current = []
            }
            for word in segment.words {
                if let first = current.first {
                    let length = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
                    if length > maxCharacters || word.end - first.start > maxDuration { flush() }
                }
                current.append(word)
            }
            flush()
        }
        return cues
    }

    static func srt(_ document: TranscriptDocument) -> String {
        cues(document).enumerated().map { index, cue in
            let text = cue.speaker.map { "\($0): \(cue.text)" } ?? cue.text
            return "\(index + 1)\n\(subtitleTime(cue.start, separator: ",")) --> \(subtitleTime(cue.end, separator: ","))\n\(wrapped(text))\n"
        }
        .joined(separator: "\n")
    }

    static func vtt(_ document: TranscriptDocument) -> String {
        let body = cues(document).map { cue in
            // WebVTT voice tags carry the speaker.
            let text = cue.speaker.map { "<v \($0)>\(wrapped(cue.text))" } ?? wrapped(cue.text)
            return "\(subtitleTime(cue.start, separator: ".")) --> \(subtitleTime(cue.end, separator: "."))\n\(text)\n"
        }
        return "WEBVTT\n\n" + body.joined(separator: "\n")
    }

    /// "01:02:03,456" (SRT) or "01:02:03.456" (WebVTT).
    static func subtitleTime(_ seconds: TimeInterval, separator: String) -> String {
        let totalMilliseconds = Int((max(seconds, 0) * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let secs = totalMilliseconds / 1_000 % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, milliseconds)
    }

    /// Breaks long cue text into two lines near the middle.
    private static func wrapped(_ text: String, lineLength: Int = 42) -> String {
        guard text.count > lineLength else { return text }
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        let before = text[..<middle].lastIndex(of: " ")
        let after = text[middle...].firstIndex(of: " ")
        let candidates = [before, after].compactMap { $0 }
        guard let split = candidates.min(by: {
            abs(text.distance(from: middle, to: $0)) < abs(text.distance(from: middle, to: $1))
        }) else { return text }
        return text[..<split] + "\n" + text[text.index(after: split)...]
    }

    // MARK: - JSON

    private struct JSONTranscript: Encodable {
        struct Segment: Encodable {
            var start: Double
            var end: Double
            var speaker: String?
            var text: String
            var words: [Word]
        }

        struct Word: Encodable {
            var text: String
            var start: Double
            var end: Double
            var confidence: Double?
        }

        var title: String
        var createdAt: Date
        var duration: Double
        var language: String?
        var engine: String
        var segments: [Segment]
    }

    static func json(_ document: TranscriptDocument) throws -> Data {
        func ms(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
        let payload = JSONTranscript(
            title: document.title,
            createdAt: document.createdAt,
            duration: ms(document.duration),
            language: document.languageCode,
            engine: document.engine,
            segments: document.segments.map { segment in
                JSONTranscript.Segment(
                    start: ms(segment.start), end: ms(segment.end), speaker: segment.speaker, text: segment.text,
                    words: segment.words.map { word in
                        JSONTranscript.Word(
                            text: word.text, start: ms(word.start), end: ms(word.end),
                            confidence: word.confidence.map { (Double($0) * 1_000).rounded() / 1_000 }
                        )
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
