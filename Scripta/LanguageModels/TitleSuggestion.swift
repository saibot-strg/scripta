import Foundation

/// Asks a language model for a short title and tidies up its answer.
enum TitleSuggestion {
    /// Room for the answer; models sometimes add a word or two of preamble.
    static let maxAnswerTokens = 48
    /// Titles longer than this are cut at a word boundary.
    static let maxWords = 8

    static func title(for transcript: TranscriptText, using engine: any LanguageModelEngine) async throws -> String {
        let empty = prompt(for: "", isComplete: true, languageCode: transcript.languageCode)
        let reserved = try await engine.tokenCount(of: empty.instructions + empty.request) + maxAnswerTokens + 64
        let budget = try await engine.contextSize() - reserved
        let excerpt = try await transcript.excerpt(maxTokens: budget) { try await engine.tokenCount(of: $0) }
        let answer = try await engine.generate(
            prompt(for: excerpt.text, isComplete: excerpt.isComplete, languageCode: transcript.languageCode),
            maxTokens: maxAnswerTokens
        )
        guard let title = cleaned(answer) else { throw LanguageModelError.emptyAnswer }
        return title
    }

    static func prompt(for text: String, isComplete: Bool, languageCode: String?) -> LanguagePrompt {
        switch PromptLanguage(languageCode) {
        case .german:
            LanguagePrompt(
                instructions: """
                Du gibst Transkripten von Aufnahmen und Besprechungen einen kurzen deutschen Titel. \
                Der Titel nennt das Hauptthema in zwei bis sechs Wörtern. \
                Kein Datum, keine Anführungszeichen, kein Punkt am Ende. Antworte nur mit dem Titel.
                """,
                request: (isComplete
                    ? "Transkript:\n\n"
                    : "Ausschnitte aus Anfang, Mitte und Ende des Transkripts:\n\n") + text + "\n\nTitel:"
            )
        case .other(let language):
            LanguagePrompt(
                instructions: """
                You give transcripts of recordings and meetings a short title in \(language). \
                The title names the main topic in two to six words. \
                No date, no quotation marks, no full stop. Answer with the title only.
                """,
                request: (isComplete
                    ? "Transcript:\n\n"
                    : "Passages from the beginning, middle and end of the transcript:\n\n") + text + "\n\nTitle:"
            )
        }
    }

    /// The title from a model's answer: first line, without labels,
    /// quotation marks, Markdown or a closing full stop; nil if nothing is left.
    static func cleaned(_ answer: String) -> String? {
        guard var line = answer
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.allSatisfy { "#*-_".contains($0) } })
        else { return nil }

        for label in ["Titel:", "Title:", "Vorschlag:", "Suggested title:"] where line.lowercased().hasPrefix(label.lowercased()) {
            line = String(line.dropFirst(label.count))
        }
        let decoration = CharacterSet(charactersIn: "\"'„“”‚‘’«»‹›`*#_").union(.whitespaces)
        line = line.trimmingCharacters(in: decoration)
        while let last = line.last, ".!:;,".contains(last) {
            line.removeLast()
            line = line.trimmingCharacters(in: decoration)
        }

        let words = line.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > maxWords {
            line = words.prefix(maxWords).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ",:;–-").union(.whitespaces))
        }
        return line.isEmpty ? nil : line
    }
}

/// German transcripts get German instructions (small models follow them
/// better); every other language gets English ones naming the language.
enum PromptLanguage: Equatable {
    case german
    case other(String)

    init(_ code: String?) {
        let code = code.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 }
        if code == "de" {
            self = .german
        } else {
            let name = code.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
            self = .other(name ?? "the language of the transcript")
        }
    }
}
