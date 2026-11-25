import Foundation

/// One request to a language model: instructions (system message) and the
/// text to work on (user message).
struct LanguagePrompt: Sendable, Equatable {
    var instructions: String
    var request: String
}

/// A loaded (or loadable) language model. Implementations run off the main
/// actor; cancelling the calling task stops a running generation.
protocol LanguageModelEngine: Sendable {
    /// Tokens the model takes at once, prompt and answer together.
    func contextSize() async throws -> Int
    func tokenCount(of text: String) async throws -> Int
    /// Generates an answer. `onText` receives the answer so far while it grows.
    func generate(
        _ prompt: LanguagePrompt,
        maxTokens: Int,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> String
    /// Frees the model's memory; the next call loads it again.
    func unload() async
}

extension LanguageModelEngine {
    func generate(_ prompt: LanguagePrompt, maxTokens: Int) async throws -> String {
        try await generate(prompt, maxTokens: maxTokens) { _ in }
    }
}

enum LanguageModelError: LocalizedError, Equatable {
    case notInstalled
    case appleIntelligenceUnavailable(String)
    case loadFailed(String)
    case generationFailed(String)
    case emptyAnswer
    case noTranscript
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            String(localized: "Das Sprachmodell ist nicht geladen. Lade es in den Einstellungen unter „Erkennung“.")
        case .appleIntelligenceUnavailable(let reason):
            reason
        case .loadFailed(let detail):
            String(localized: "Das Sprachmodell konnte nicht geladen werden: \(detail)")
        case .generationFailed(let detail):
            String(localized: "Das Sprachmodell hat keine Antwort geliefert: \(detail)")
        case .emptyAnswer:
            String(localized: "Das Sprachmodell hat keine brauchbare Antwort geliefert.")
        case .noTranscript:
            String(localized: "Diese Aufnahme hat noch kein Transkript.")
        case .fileUnavailable:
            String(localized: "Die Modelldatei ist nicht mehr erreichbar. Wähle sie in den Einstellungen erneut aus.")
        }
    }
}

/// Clean-up shared by all engines.
enum ModelOutput {
    /// Removes reasoning blocks (`<think>…</think>` and similar) that some
    /// models write before the answer, also an unfinished one while streaming.
    static func strippingReasoning(_ text: String) -> String {
        var result = text
        for (open, close) in [("<think>", "</think>"), ("<|channel>thought", "<channel|>")] {
            while let start = result.range(of: open) {
                if let end = result.range(of: close, range: start.upperBound..<result.endIndex) {
                    result.removeSubrange(start.lowerBound..<end.upperBound)
                } else {
                    result.removeSubrange(start.lowerBound..<result.endIndex)
                }
            }
            // A template that opens the block itself leaves only the closing tag.
            if let end = result.range(of: close) {
                result.removeSubrange(result.startIndex..<end.upperBound)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
