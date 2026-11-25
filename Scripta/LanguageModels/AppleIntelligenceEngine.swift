import Foundation
import FoundationModels

/// Apple's on-device model (Apple Intelligence). Nothing to download and no
/// memory in Scripta's process, but a small context (4,096 tokens on macOS 26).
struct AppleIntelligenceEngine: LanguageModelEngine {
    /// Transcripts quote people verbatim; the default guardrails flag
    /// harmless meetings now and then.
    private var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    /// Why the model can't be used right now, or nil if it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            String(localized: "Dieser Mac unterstützt Apple Intelligence nicht.")
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "Apple Intelligence ist ausgeschaltet. Du kannst es in den Systemeinstellungen unter „Apple Intelligence & Siri“ einschalten.")
        case .unavailable(.modelNotReady):
            String(localized: "Apple Intelligence wird noch vorbereitet. Versuche es später erneut.")
        case .unavailable:
            String(localized: "Apple Intelligence ist gerade nicht verfügbar.")
        }
    }

    func contextSize() async throws -> Int {
        SystemLanguageModel.default.contextSize
    }

    func tokenCount(of text: String) async throws -> Int {
        if #available(macOS 26.4, *) {
            return try await SystemLanguageModel.default.tokenCount(for: text)
        }
        // Measured on German transcripts: about 1.6 tokens per word, ~3.5 characters per token.
        return text.count * 2 / 7 + 1
    }

    func generate(
        _ prompt: LanguagePrompt,
        maxTokens: Int,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if let reason = Self.unavailableReason {
            throw LanguageModelError.appleIntelligenceUnavailable(reason)
        }
        let session = LanguageModelSession(model: model, instructions: prompt.instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)
        var text = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt.request, options: options) {
                text = snapshot.content
                onText(ModelOutput.strippingReasoning(text))
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw LanguageModelError.generationFailed(error.localizedDescription)
        }
        return ModelOutput.strippingReasoning(text)
    }

    func unload() async {}
}
