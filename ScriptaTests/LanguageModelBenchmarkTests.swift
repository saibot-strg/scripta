import Darwin
import Foundation
import Testing
@testable import Scripta

/// Titles and summaries with real models on real transcripts. Opt-in: it
/// downloads several GB and takes minutes.
///
///     TEST_RUNNER_SCRIPTA_LLM_BENCHMARK=1 \
///     TEST_RUNNER_SCRIPTA_LLM_MODELS=qwen3.5-4b-mlx,gemma4-e2b-gguf \
///     xcodebuild test -only-testing:ScriptaTests/LanguageModelBenchmarkTests …
///
/// Transcripts: plain text files (one paragraph per line) in the test
/// host's temporary folder, `tmp/llm-benchmark/*.txt`.
@Suite(
    "Language model benchmark",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCRIPTA_LLM_BENCHMARK"] == "1")
)
struct LanguageModelBenchmarkTests {
    static let modelIDs = (ProcessInfo.processInfo.environment["SCRIPTA_LLM_MODELS"] ?? "apple-intelligence")
        .split(separator: ",").map(String.init)

    static var transcripts: [(name: String, text: TranscriptText)] {
        let folder = URL.temporaryDirectory.appending(path: "llm-benchmark")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let paragraphs = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return (url.deletingPathExtension().lastPathComponent, TranscriptText(paragraphs: paragraphs, languageCode: "de"))
        }
    }

    @Test("Titles and summaries", arguments: modelIDs)
    func titlesAndSummaries(modelID: String) async throws {
        let model = try #require(LanguageModelCatalog.model(withID: modelID))
        let downloader = LanguageModelDownloader()
        if !downloader.isInstalled(model) {
            let started = ContinuousClock.now
            try await downloader.download(model) { _ in }
            print("BENCHMARK \(model.name): downloaded in \(ContinuousClock.now - started)")
        }
        let engine: any LanguageModelEngine = switch model.runtime {
        case .apple: AppleIntelligenceEngine()
        case .mlx: MLXEngine(directory: downloader.localURL(for: model), contextBudget: model.contextBudget)
        case .gguf: LlamaEngine(fileURL: downloader.localURL(for: model), contextBudget: model.contextBudget)
        }
        let transcripts = Self.transcripts
        try #require(!transcripts.isEmpty, "no transcripts in tmp/llm-benchmark")
        let memoryBefore = footprint()

        for (name, transcript) in transcripts {
            let tokens = try await engine.tokenCount(of: transcript.text)
            var started = ContinuousClock.now
            let title = try await TitleSuggestion.title(for: transcript, using: engine)
            let titleTime = ContinuousClock.now - started
            print("BENCHMARK \(model.name) | \(name) | \(transcript.wordCount) words, \(tokens) tokens | title (\(titleTime)): \(title)")
            #expect(!title.isEmpty)

            guard model.canSummarize else { continue }
            started = ContinuousClock.now
            let summary = try await SummaryGeneration.summary(of: transcript, using: engine) { _ in }
            let summaryTime = ContinuousClock.now - started
            let growth = Double(footprint() - min(memoryBefore, footprint())) / 1_073_741_824
            print("BENCHMARK \(model.name) | \(name) | summary (\(summaryTime), footprint +\(String(format: "%.1f", growth)) GB):\n\(summary)\n")
            #expect(summary.count > 100)
        }
        await engine.unload()
    }

    /// Memory charged to the process, including GPU buffers.
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
