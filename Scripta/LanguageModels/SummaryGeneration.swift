import Foundation

/// Writes a summary (short version, key points, tasks, decisions) of a
/// transcript. Transcripts longer than the model's context are summarized
/// part by part first, then the part summaries are merged.
enum SummaryGeneration {
    static let maxAnswerTokens = 1200
    /// Room for the notes on one part (map step).
    static let maxPartAnswerTokens = 400

    enum Progress: Equatable, Sendable {
        /// Summarizing part `index` (1-based) of `count`.
        case part(index: Int, count: Int)
        /// Writing the summary; the text so far.
        case writing(String)
    }

    static func summary(
        of transcript: TranscriptText,
        using engine: any LanguageModelEngine,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws -> String {
        let language = PromptLanguage(transcript.languageCode)
        let context = try await engine.contextSize()
        let finalPrompt = prompt(for: "", language: language, fromParts: false)
        let available = context - maxAnswerTokens - 64
            - (try await engine.tokenCount(of: finalPrompt.instructions + finalPrompt.request))

        var text = transcript.text
        var fromParts = false
        if try await engine.tokenCount(of: text) > available {
            let partPrompt = self.partPrompt(for: "", index: 1, count: 1, language: language)
            let partBudget = context - maxPartAnswerTokens - 64
                - (try await engine.tokenCount(of: partPrompt.instructions + partPrompt.request))
            let parts = try await transcript.parts(maxTokens: partBudget) { try await engine.tokenCount(of: $0) }
            var notes: [String] = []
            for (index, part) in parts.enumerated() {
                progress(.part(index: index + 1, count: parts.count))
                let answer = try await engine.generate(
                    self.partPrompt(for: part, index: index + 1, count: parts.count, language: language),
                    maxTokens: maxPartAnswerTokens
                )
                notes.append(partHeading(index + 1, language: language) + "\n" + answer)
            }
            text = notes.joined(separator: "\n\n")
            fromParts = true
            // Very long recordings with a small model: keep the notes within the context.
            if try await engine.tokenCount(of: text) > available {
                text = try await TranscriptText(paragraphs: notes, languageCode: transcript.languageCode)
                    .excerpt(maxTokens: available, passages: 4) { try await engine.tokenCount(of: $0) }.text
            }
        }

        progress(.writing(""))
        let answer = try await engine.generate(
            prompt(for: text, language: language, fromParts: fromParts),
            maxTokens: maxAnswerTokens
        ) { partial in
            progress(.writing(partial))
        }
        let summary = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw LanguageModelError.emptyAnswer }
        return summary
    }

    static func prompt(for text: String, language: PromptLanguage, fromParts: Bool) -> LanguagePrompt {
        switch language {
        case .german:
            LanguagePrompt(
                instructions: """
                Du fasst Transkripte von Besprechungen und Aufnahmen sachlich auf Deutsch zusammen. \
                Schreib nur, was im Transkript steht, und erfinde nichts dazu. \
                „Ich“ ist die Person, die aufgenommen hat. \
                Antworte in Markdown mit diesen Abschnitten und lass leere Abschnitte weg:
                ## Kurzfassung
                Drei bis fünf Sätze.
                ## Kernpunkte
                - Stichpunkte
                ## Aufgaben
                - Wer macht was, bis wann (falls genannt)
                ## Entscheidungen
                - Stichpunkte
                """,
                request: (fromParts
                    ? "Notizen zu den Teilen eines langen Transkripts:\n\n"
                    : "Transkript:\n\n") + text
            )
        case .other(let name):
            LanguagePrompt(
                instructions: """
                You summarize transcripts of meetings and recordings factually, in \(name). \
                Only write what the transcript says; do not make anything up. \
                "Ich" or "Me" is the person who recorded. \
                Answer in Markdown with these sections (translated into \(name)) and leave out empty ones:
                ## Summary
                Three to five sentences.
                ## Key points
                - Bullet points
                ## Tasks
                - Who does what, by when (if mentioned)
                ## Decisions
                - Bullet points
                """,
                request: (fromParts
                    ? "Notes on the parts of a long transcript:\n\n"
                    : "Transcript:\n\n") + text
            )
        }
    }

    static func partPrompt(for text: String, index: Int, count: Int, language: PromptLanguage) -> LanguagePrompt {
        switch language {
        case .german:
            LanguagePrompt(
                instructions: """
                Du machst knappe Notizen zu einem Teil eines langen Transkripts. \
                Schreib Stichpunkte zu Themen, Aufgaben (wer, was) und Entscheidungen. \
                Schreib nur, was im Text steht.
                """,
                request: "Teil \(index) von \(count):\n\n\(text)"
            )
        case .other(let name):
            LanguagePrompt(
                instructions: """
                You take brief notes, in \(name), on one part of a long transcript. \
                Write bullet points on topics, tasks (who, what) and decisions. \
                Only write what the text says.
                """,
                request: "Part \(index) of \(count):\n\n\(text)"
            )
        }
    }

    private static func partHeading(_ index: Int, language: PromptLanguage) -> String {
        language == .german ? "Teil \(index):" : "Part \(index):"
    }
}
