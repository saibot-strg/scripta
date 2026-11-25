import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import os

/// A model in MLX format (a downloaded Hugging Face folder), run on the GPU.
actor MLXEngine: LanguageModelEngine {
    private let directory: URL
    private let budget: Int
    private var container: ModelContainer?

    init(directory: URL, contextBudget: Int) {
        self.directory = directory
        self.budget = contextBudget
    }

    func contextSize() async throws -> Int { budget }

    func tokenCount(of text: String) async throws -> Int {
        let container = try await load()
        return await container.encode(text).count
    }

    func generate(
        _ prompt: LanguagePrompt,
        maxTokens: Int,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let container = try await load()
        let input = UserInput(
            chat: [.system(prompt.instructions), .user(prompt.request)],
            // Qwen 3.5 thinks before answering by default: slow, and not needed here.
            additionalContext: ["enable_thinking": false]
        )
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.3, topP: 0.9, repetitionPenalty: 1.05)
        var text = ""
        do {
            let prepared = try await container.prepare(input: input)
            for await generation in try await container.generate(input: prepared, parameters: parameters) {
                try Task.checkCancellation()
                guard case .chunk(let chunk) = generation else { continue }
                text += chunk
                onText(ModelOutput.strippingReasoning(text))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LanguageModelError.generationFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        return ModelOutput.strippingReasoning(text)
    }

    func unload() async {
        guard container != nil else { return }
        container = nil
        Memory.clearCache()
        Logger.languageModels.notice("MLX model unloaded")
    }

    private func load() async throws -> ModelContainer {
        if let container { return container }
        // Without a limit, MLX keeps freed GPU buffers for reuse indefinitely.
        Memory.cacheLimit = 256 * 1024 * 1024
        do {
            let container = try await loadModelContainer(from: directory, using: TransformersTokenizerLoader())
            self.container = container
            Logger.languageModels.notice("MLX model loaded: \(self.directory.lastPathComponent, privacy: .public)")
            return container
        } catch {
            throw LanguageModelError.loadFailed(error.localizedDescription)
        }
    }
}

/// Loads the tokenizer of an MLX model folder with swift-transformers.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// swift-transformers' tokenizer in the shape mlx-swift-lm expects.
private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
