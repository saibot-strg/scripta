import Foundation

/// The transcript as plain text for a language model, and the parts of it
/// that fit into a model's context.
struct TranscriptText: Sendable, Equatable {
    /// One paragraph per speaker turn.
    let paragraphs: [String]
    /// BCP-47 code of the transcript ("de", "en" …), if known.
    let languageCode: String?

    var text: String { paragraphs.joined(separator: "\n") }
    var wordCount: Int { paragraphs.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count } }

    init(paragraphs: [String], languageCode: String?) {
        self.paragraphs = paragraphs
        self.languageCode = languageCode
    }

    /// `namesSpeakers`: "Anna: …" in front of each turn (summaries: who
    /// said what); titles get the bare text.
    @MainActor
    init(_ transcript: Transcript, namesSpeakers: Bool) {
        let showsNames = namesSpeakers && transcript.hasSpeakers
        var paragraphs: [String] = []
        var currentSpeaker: UUID?
        var current: [String] = []
        var currentName = ""
        func flush() {
            guard !current.isEmpty else { return }
            let text = current.joined(separator: " ")
            paragraphs.append(showsNames ? "\(currentName): \(text)" : text)
            current = []
        }
        for segment in transcript.orderedSegments {
            let speakerID = segment.speaker?.id
            if speakerID != currentSpeaker {
                flush()
                currentSpeaker = speakerID
                currentName = segment.speaker?.displayName ?? ""
            }
            current.append(segment.text)
        }
        flush()
        self.init(paragraphs: paragraphs, languageCode: transcript.languageCode)
    }

    /// Up to `maxTokens` of the transcript: all of it if it fits, otherwise
    /// evenly spaced passages (beginning, middle, end) that cover the
    /// whole conversation instead of only its first minutes.
    func excerpt(
        maxTokens: Int,
        passages: Int = 3,
        countTokens: (String) async throws -> Int
    ) async throws -> (text: String, isComplete: Bool) {
        let full = text
        let total = try await countTokens(full)
        if total <= maxTokens { return (full, true) }

        let words = full.split(whereSeparator: \.isWhitespace)
        // Words per token measured on this transcript; shrink until it fits.
        var wordBudget = Int(Double(words.count) * Double(maxTokens) / Double(total) * 0.95)
        while wordBudget > passages * 20 {
            let excerpt = Self.passages(of: words, count: passages, totalWords: wordBudget)
            if try await countTokens(excerpt) <= maxTokens { return (excerpt, false) }
            wordBudget = wordBudget * 9 / 10
        }
        return (Self.passages(of: words, count: passages, totalWords: wordBudget), false)
    }

    /// `count` passages of `totalWords` words in all, evenly spread, the
    /// first at the start and the last at the end.
    static func passages(of words: [Substring], count: Int, totalWords: Int) -> String {
        let length = max(1, totalWords / count)
        guard words.count > length * count else { return words.joined(separator: " ") }
        let lastStart = words.count - length
        return (0..<count).map { index in
            let start = count == 1 ? 0 : lastStart * index / (count - 1)
            return words[start..<start + length].joined(separator: " ")
        }
        .joined(separator: "\n[…]\n")
    }

    /// Splits the transcript into parts of at most `maxTokens` each, at
    /// paragraph boundaries where possible (long summaries, map step).
    func parts(maxTokens: Int, countTokens: (String) async throws -> Int) async throws -> [String] {
        let total = try await countTokens(text)
        if total <= maxTokens { return [text] }
        let tokensPerWord = Double(total) / Double(max(wordCount, 1))
        let targetWords = max(50, Int(Double(maxTokens) / tokensPerWord * 0.9))

        // Paragraphs longer than a part are cut into pieces first.
        var pieces: [String] = []
        for paragraph in paragraphs {
            let words = paragraph.split(whereSeparator: \.isWhitespace)
            stride(from: 0, to: words.count, by: targetWords).forEach { start in
                pieces.append(words[start..<min(start + targetWords, words.count)].joined(separator: " "))
            }
        }

        var parts: [String] = []
        var current: [String] = []
        var currentWords = 0
        for piece in pieces {
            let count = piece.split(whereSeparator: \.isWhitespace).count
            if currentWords + count > targetWords, !current.isEmpty {
                parts.append(current.joined(separator: "\n"))
                current = []
                currentWords = 0
            }
            current.append(piece)
            currentWords += count
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n")) }

        // The estimate can be off for single parts: split those again.
        var checked: [String] = []
        for part in parts {
            if try await countTokens(part) <= maxTokens {
                checked.append(part)
            } else {
                let words = part.split(whereSeparator: \.isWhitespace)
                let half = words.count / 2
                checked.append(words[..<half].joined(separator: " "))
                checked.append(words[half...].joined(separator: " "))
            }
        }
        return checked
    }
}
