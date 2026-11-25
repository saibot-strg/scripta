import Foundation

/// A language model Scripta can use for titles and summaries.
struct LanguageModelDescriptor: Identifiable, Hashable, Sendable {
    enum Runtime: String, Hashable, Sendable {
        /// Apple Intelligence, built into macOS.
        case apple
        /// A Hugging Face repository in MLX format, run on the GPU via mlx-swift.
        case mlx
        /// A single GGUF file, run on the GPU via llama.cpp.
        case gguf
    }

    let id: String
    let name: String
    let runtime: Runtime
    /// Hugging Face repository (downloadable models only).
    let repository: String?
    /// The GGUF file in `repository`; MLX models load every file of the repository.
    let fileName: String?
    /// Approximate download size in bytes (0 = nothing to download).
    let downloadSize: Int64
    /// Tokens Scripta gives the model at once, prompt and answer together.
    /// Chosen so the cache stays around 1 GB; longer transcripts are summarized in parts.
    let contextBudget: Int
    let isRecommended: Bool
    /// A file the user chose ("Eigene GGUF-Datei …").
    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    static let customPrefix = "custom:"

    init(
        id: String,
        name: String,
        runtime: Runtime,
        repository: String? = nil,
        fileName: String? = nil,
        downloadSize: Int64 = 0,
        contextBudget: Int,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.runtime = runtime
        self.repository = repository
        self.fileName = fileName
        self.downloadSize = downloadSize
        self.contextBudget = contextBudget
        self.isRecommended = isRecommended
    }

    /// Only downloaded models can summarize: Apple Intelligence sees too
    /// little of a meeting at once (about 2,000 words).
    var canSummarize: Bool { runtime != .apple }

    /// Short note for the settings list ("MLX · 3,1 GB").
    var runtimeLabel: String {
        switch runtime {
        case .apple: String(localized: "In macOS integriert")
        case .mlx: "MLX"
        case .gguf: "GGUF · llama.cpp"
        }
    }
}

/// The models offered in Settings › Erkennung. All are Apache 2.0 and
/// can be downloaded without an account (checked 2026-10-26).
enum LanguageModelCatalog {
    static let appleIntelligence = LanguageModelDescriptor(
        id: "apple-intelligence",
        name: "Apple Intelligence",
        runtime: .apple,
        contextBudget: 4096
    )

    static let qwen35_4B = LanguageModelDescriptor(
        id: "qwen3.5-4b-mlx",
        name: "Qwen 3.5 4B",
        runtime: .mlx,
        repository: "mlx-community/Qwen3.5-4B-MLX-4bit",
        downloadSize: 3_060_000_000,
        contextBudget: 32_768,
        isRecommended: true
    )

    static let all: [LanguageModelDescriptor] = [
        appleIntelligence,
        qwen35_4B,
        LanguageModelDescriptor(
            id: "qwen3.5-2b-mlx",
            name: "Qwen 3.5 2B",
            runtime: .mlx,
            repository: "mlx-community/Qwen3.5-2B-MLX-4bit",
            downloadSize: 1_750_000_000,
            contextBudget: 32_768
        ),
        LanguageModelDescriptor(
            id: "ministral3-3b-gguf",
            name: "Ministral 3 3B",
            runtime: .gguf,
            repository: "mistralai/Ministral-3-3B-Instruct-2512-GGUF",
            fileName: "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf",
            downloadSize: 2_147_023_008,
            // Every layer keeps a full cache (~100 KB per token).
            contextBudget: 16_384
        ),
        LanguageModelDescriptor(
            id: "gemma4-e2b-gguf",
            name: "Gemma 4 E2B",
            runtime: .gguf,
            repository: "google/gemma-4-E2B-it-qat-q4_0-gguf",
            fileName: "gemma-4-E2B_q4_0-it.gguf",
            downloadSize: 3_349_516_256,
            contextBudget: 32_768
        ),
        LanguageModelDescriptor(
            id: "gemma4-e4b-gguf",
            name: "Gemma 4 E4B",
            runtime: .gguf,
            repository: "google/gemma-4-E4B-it-qat-q4_0-gguf",
            fileName: "gemma-4-E4B_q4_0-it.gguf",
            downloadSize: 5_154_941_280,
            contextBudget: 32_768
        ),
    ]

    static func model(withID id: String) -> LanguageModelDescriptor? {
        all.first { $0.id == id }
    }

    /// A GGUF file the user picked. Its context is kept small: nothing is
    /// known about its memory use.
    static func custom(fileName: String) -> LanguageModelDescriptor {
        LanguageModelDescriptor(
            id: LanguageModelDescriptor.customPrefix + fileName,
            name: (fileName as NSString).deletingPathExtension,
            runtime: .gguf,
            fileName: fileName,
            contextBudget: 8192
        )
    }
}
