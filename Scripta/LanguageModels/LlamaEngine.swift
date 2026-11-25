import Foundation
import Jinja
import LlamaSwift
import os

/// A GGUF model run on the GPU with llama.cpp.
///
/// The prompt is built from the chat template stored in the GGUF file
/// (rendered with Jinja), so new model families work without code changes.
/// llama.cpp's own template matching is only the fallback: it doesn't know
/// Gemma 4, for example.
actor LlamaEngine: LanguageModelEngine {
    private let fileURL: URL
    private let budget: Int
    private var model: OpaquePointer?
    private var chatTemplate: Template?

    /// Tokens prefilled per `llama_decode` call; cancellation is checked between them.
    private static let batchSize = 512

    init(fileURL: URL, contextBudget: Int) {
        self.fileURL = fileURL
        self.budget = contextBudget
    }

    func contextSize() async throws -> Int {
        let model = try load()
        let trained = Int(llama_model_n_ctx_train(model))
        return trained > 0 ? min(budget, trained) : budget
    }

    func tokenCount(of text: String) async throws -> Int {
        try tokenize(text, vocab: llama_model_get_vocab(try load())).count
    }

    func generate(
        _ prompt: LanguagePrompt,
        maxTokens: Int,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let model = try load()
        guard let vocab = llama_model_get_vocab(model) else { throw LanguageModelError.loadFailed("vocabulary") }
        var tokens = try tokenize(try render(prompt, vocab: vocab), vocab: vocab)
        let bos = llama_vocab_bos(vocab)
        if llama_vocab_get_add_bos(vocab), bos >= 0, tokens.first != bos {
            tokens.insert(bos, at: 0)
        }

        var parameters = llama_context_default_params()
        // Only as much cache as this request needs, rounded up.
        parameters.n_ctx = UInt32((tokens.count + maxTokens + 255) / 256 * 256)
        parameters.n_batch = UInt32(Self.batchSize)
        parameters.n_ubatch = UInt32(Self.batchSize)
        parameters.no_perf = true
        guard let context = llama_init_from_model(model, parameters) else {
            throw LanguageModelError.loadFailed(String(localized: "Zu wenig Arbeitsspeicher"))
        }
        defer { llama_free(context) }

        var start = 0
        while start < tokens.count {
            try Task.checkCancellation()
            let end = min(start + Self.batchSize, tokens.count)
            try decode(Array(tokens[start..<end]), in: context)
            start = end
        }

        let sampler = Self.makeSampler(vocab: vocab)
        defer { llama_sampler_free(sampler) }
        var bytes: [UInt8] = []
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(of: token, vocab: vocab)
            let text = String(decoding: bytes, as: UTF8.self)
            // Wait for the rest of a character split across tokens.
            if !text.hasSuffix("\u{FFFD}") {
                onText(ModelOutput.strippingReasoning(text))
            }
            try decode([token], in: context)
        }
        return ModelOutput.strippingReasoning(String(decoding: bytes, as: UTF8.self))
    }

    func unload() async {
        guard let model else { return }
        llama_model_free(model)
        self.model = nil
        chatTemplate = nil
        Logger.languageModels.notice("GGUF model unloaded")
    }

    // MARK: - Loading

    private static let backend: Void = {
        llama_log_set({ level, text, _ in
            guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
            Logger.languageModels.error("llama.cpp: \(String(cString: text), privacy: .public)")
        }, nil)
        llama_backend_init()
    }()

    private func load() throws -> OpaquePointer {
        if let model { return model }
        _ = Self.backend
        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(fileURL.path(percentEncoded: false), parameters) else {
            throw LanguageModelError.loadFailed(fileURL.lastPathComponent)
        }
        self.model = model
        if let source = llama_model_chat_template(model, nil) {
            chatTemplate = try? Template(String(cString: source), with: .init(lstripBlocks: true, trimBlocks: true))
        }
        Logger.languageModels.notice("GGUF model loaded: \(self.fileURL.lastPathComponent, privacy: .public)")
        return model
    }

    // MARK: - Prompt

    /// The chat as the model was trained to see it, ending where the
    /// assistant's answer begins.
    private func render(_ prompt: LanguagePrompt, vocab: OpaquePointer) throws -> String {
        if let chatTemplate {
            let special = { (token: llama_token) in token >= 0 ? llama_vocab_get_text(vocab, token).map { String(cString: $0) } ?? "" : "" }
            var context: [String: Value] = [
                "add_generation_prompt": .boolean(true),
                "enable_thinking": .boolean(false),
                "bos_token": .string(special(llama_vocab_bos(vocab))),
                "eos_token": .string(special(llama_vocab_eos(vocab))),
            ]
            let withSystem = [["role": "system", "content": prompt.instructions], ["role": "user", "content": prompt.request]]
            // Some templates reject a system message: then it goes in front of the request.
            let merged = [["role": "user", "content": prompt.instructions + "\n\n" + prompt.request]]
            for messages in [withSystem, merged] {
                context["messages"] = try Value(any: messages)
                if let rendered = try? chatTemplate.render(context) { return rendered }
            }
        }
        return try Self.applyBuiltInTemplate(prompt, model: model)
    }

    private static func applyBuiltInTemplate(_ prompt: LanguagePrompt, model: OpaquePointer?) throws -> String {
        let template = model.flatMap { llama_model_chat_template($0, nil) }
        return try withChatMessages(prompt) { messages, count in
            let length = llama_chat_apply_template(template, messages, count, true, nil, 0)
            guard length > 0 else { throw LanguageModelError.generationFailed("chat template") }
            var buffer = [CChar](repeating: 0, count: Int(length) + 1)
            _ = llama_chat_apply_template(template, messages, count, true, &buffer, Int32(buffer.count))
            return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    private static func withChatMessages<R>(
        _ prompt: LanguagePrompt,
        _ body: (UnsafePointer<llama_chat_message>, Int) throws -> R
    ) throws -> R {
        let strings = [strdup("system"), strdup(prompt.instructions), strdup("user"), strdup(prompt.request)]
        defer { strings.forEach { free($0) } }
        let messages = [
            llama_chat_message(role: strings[0], content: strings[1]),
            llama_chat_message(role: strings[2], content: strings[3]),
        ]
        return try messages.withUnsafeBufferPointer { try body($0.baseAddress!, $0.count) }
    }

    // MARK: - Tokens

    private func tokenize(_ text: String, vocab: OpaquePointer?) throws -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
        var count = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), false, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), false, true)
        }
        guard count >= 0 else { throw LanguageModelError.generationFailed("tokenize") }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(of token: llama_token, vocab: OpaquePointer) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        return buffer.prefix(Int(max(length, 0))).map { UInt8(bitPattern: $0) }
    }

    private func decode(_ tokens: [llama_token], in context: OpaquePointer) throws {
        var tokens = tokens
        let result = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        guard result == 0 else { throw LanguageModelError.generationFailed("decode \(result)") }
    }

    /// Top-k first: the repetition penalty is slow on the full vocabulary.
    private static func makeSampler(vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.05, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        return sampler
    }
}
