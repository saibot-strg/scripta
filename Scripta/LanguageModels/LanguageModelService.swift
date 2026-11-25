import Foundation
import os

/// Language models for titles and summaries: the catalog with download
/// states, the chosen models, and the jobs. Jobs run one after another;
/// a downloaded model waits until no transcription runs, so it never
/// competes with Parakeet for memory.
@MainActor
@Observable
final class LanguageModelService {
    enum InstallState: Equatable {
        case notInstalled
        case downloading(fraction: Double)
        case installed
        case failed(message: String)
    }

    /// A summary being written, for the detail view.
    struct SummaryJob: Equatable {
        var progress: SummaryGeneration.Progress?
    }

    private(set) var installStates: [String: InstallState] = [:]
    private(set) var customModels: [LanguageModelDescriptor] = []
    /// Recordings whose title is being generated or waits for it.
    private(set) var titleJobs: Set<UUID> = []
    private(set) var summaryJobs: [UUID: SummaryJob] = [:]
    /// Summaries read from disk or just written, by recording ID.
    private(set) var summaries: [UUID: TranscriptSummary] = [:]
    /// Recordings whose summary file was looked for, found or not.
    private(set) var checkedSummaryIDs: Set<UUID> = []

    var titleModelID: String {
        didSet { defaults.set(titleModelID, forKey: SettingsKey.titleModel) }
    }
    var summaryModelID: String {
        didSet { defaults.set(summaryModelID, forKey: SettingsKey.summaryModel) }
    }

    /// True while a transcription runs; set by the app model.
    @ObservationIgnored var isTranscribing: @MainActor () -> Bool = { false }

    let downloader: LanguageModelDownloader
    /// False: no models at all (tests and previews that don't need them).
    let isEnabled: Bool
    private let defaults: UserDefaults
    @ObservationIgnored private var downloads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var engines: [String: any LanguageModelEngine] = [:]
    /// Resolved custom GGUF files, kept accessible while the app runs.
    @ObservationIgnored private var customFileURLs: [String: URL] = [:]
    @ObservationIgnored private var lastJob: Task<Void, Never>?
    @ObservationIgnored private var summaryTasks: [UUID: Task<Void, any Error>] = [:]
    @ObservationIgnored private var idleUnload: Task<Void, Never>?
    @ObservationIgnored private let makeEngine: @MainActor (LanguageModelDescriptor, URL) -> any LanguageModelEngine

    /// A loaded model takes several GB; free it soon after the last job.
    static let idleUnloadDelay: Duration = .seconds(120)

    init(
        downloader: LanguageModelDownloader = LanguageModelDownloader(),
        defaults: UserDefaults = .standard,
        isEnabled: Bool = true,
        makeEngine: (@MainActor (LanguageModelDescriptor, URL) -> any LanguageModelEngine)? = nil
    ) {
        self.downloader = downloader
        self.isEnabled = isEnabled
        self.defaults = defaults
        self.makeEngine = makeEngine ?? Self.defaultEngine
        titleModelID = defaults.string(forKey: SettingsKey.titleModel) ?? LanguageModelCatalog.appleIntelligence.id
        summaryModelID = defaults.string(forKey: SettingsKey.summaryModel) ?? LanguageModelCatalog.qwen35_4B.id
        customModels = Self.loadCustomModels(from: defaults)
        refreshInstallStates()
    }

    private static func defaultEngine(_ model: LanguageModelDescriptor, url: URL) -> any LanguageModelEngine {
        switch model.runtime {
        case .apple: AppleIntelligenceEngine()
        case .mlx: MLXEngine(directory: url, contextBudget: model.contextBudget)
        case .gguf: LlamaEngine(fileURL: url, contextBudget: model.contextBudget)
        }
    }

    // MARK: - Models

    var allModels: [LanguageModelDescriptor] {
        isEnabled ? LanguageModelCatalog.all + customModels : []
    }

    func model(withID id: String) -> LanguageModelDescriptor? {
        allModels.first { $0.id == id }
    }

    /// Ready to use: Apple Intelligence switched on, or the model on disk.
    func isUsable(_ model: LanguageModelDescriptor) -> Bool {
        switch model.runtime {
        case .apple: AppleIntelligenceEngine.unavailableReason == nil
        case .mlx, .gguf: installStates[model.id] == .installed
        }
    }

    /// The model for titles: the chosen one, else any usable one.
    var titleModel: LanguageModelDescriptor? {
        if let chosen = model(withID: titleModelID), isUsable(chosen) { return chosen }
        return allModels.first(where: isUsable)
    }

    /// The model for summaries: the chosen one, else any usable downloaded one.
    var summaryModel: LanguageModelDescriptor? {
        if let chosen = model(withID: summaryModelID), chosen.canSummarize, isUsable(chosen) { return chosen }
        return allModels.first { $0.canSummarize && isUsable($0) }
    }

    func refreshInstallStates() {
        for model in allModels where model.runtime != .apple {
            if case .downloading = installStates[model.id] { continue }
            let installed = model.isCustom ? customFileURL(for: model) != nil : downloader.isInstalled(model)
            installStates[model.id] = installed ? .installed : .notInstalled
        }
    }

    func download(_ model: LanguageModelDescriptor) {
        guard downloads[model.id] == nil, model.repository != nil else { return }
        installStates[model.id] = .downloading(fraction: 0)
        let downloader = downloader
        downloads[model.id] = Task {
            defer { downloads[model.id] = nil }
            do {
                try await downloader.download(model) { fraction in
                    Task { @MainActor in
                        guard case .downloading = self.installStates[model.id] else { return }
                        self.installStates[model.id] = .downloading(fraction: fraction)
                    }
                }
                installStates[model.id] = .installed
            } catch is CancellationError {
                installStates[model.id] = .notInstalled
            } catch let error as URLError where error.code == .cancelled {
                installStates[model.id] = .notInstalled
            } catch {
                Logger.languageModels.error("Download of \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                installStates[model.id] = .failed(message: error.localizedDescription)
            }
        }
    }

    func cancelDownload(_ model: LanguageModelDescriptor) {
        downloads[model.id]?.cancel()
    }

    func delete(_ model: LanguageModelDescriptor) async {
        cancelDownload(model)
        if let engine = engines.removeValue(forKey: model.id) { await engine.unload() }
        if model.isCustom {
            customModels.removeAll { $0.id == model.id }
            customFileURLs[model.id]?.stopAccessingSecurityScopedResource()
            customFileURLs[model.id] = nil
            saveCustomModels()
            installStates[model.id] = nil
        } else {
            do {
                try downloader.delete(model)
            } catch {
                Logger.languageModels.error("Could not delete \(model.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            installStates[model.id] = .notInstalled
        }
    }

    // MARK: - Custom GGUF files

    private struct StoredCustomModel: Codable {
        var fileName: String
        var bookmark: Data
    }

    /// Adds a GGUF file the user picked; it stays where it is.
    func addCustomModel(at url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let model = LanguageModelCatalog.custom(fileName: url.lastPathComponent)
        var stored = Self.storedCustomModels(in: defaults).filter { $0.fileName != model.fileName }
        stored.append(StoredCustomModel(fileName: url.lastPathComponent, bookmark: bookmark))
        defaults.set(try JSONEncoder().encode(stored), forKey: SettingsKey.customLanguageModels)
        customModels = Self.loadCustomModels(from: defaults)
        customFileURLs[model.id] = nil
        refreshInstallStates()
    }

    private func saveCustomModels() {
        let stored = Self.storedCustomModels(in: defaults).filter { stored in
            customModels.contains { $0.fileName == stored.fileName }
        }
        defaults.set(try? JSONEncoder().encode(stored), forKey: SettingsKey.customLanguageModels)
    }

    private static func storedCustomModels(in defaults: UserDefaults) -> [StoredCustomModel] {
        guard let data = defaults.data(forKey: SettingsKey.customLanguageModels) else { return [] }
        return (try? JSONDecoder().decode([StoredCustomModel].self, from: data)) ?? []
    }

    private static func loadCustomModels(from defaults: UserDefaults) -> [LanguageModelDescriptor] {
        storedCustomModels(in: defaults).map { LanguageModelCatalog.custom(fileName: $0.fileName) }
    }

    /// Resolves the bookmark once and keeps access for the app's lifetime.
    private func customFileURL(for model: LanguageModelDescriptor) -> URL? {
        if let url = customFileURLs[model.id] { return url }
        guard let stored = Self.storedCustomModels(in: defaults).first(where: { $0.fileName == model.fileName }) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: stored.bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            url.stopAccessingSecurityScopedResource()
            return nil
        }
        customFileURLs[model.id] = url
        return url
    }

    // MARK: - Engines

    private func engine(for model: LanguageModelDescriptor) async throws -> any LanguageModelEngine {
        if let engine = engines[model.id] { return engine }
        let url: URL
        switch model.runtime {
        case .apple:
            if let reason = AppleIntelligenceEngine.unavailableReason {
                throw LanguageModelError.appleIntelligenceUnavailable(reason)
            }
            url = downloader.rootURL
        case .mlx, .gguf:
            if model.isCustom {
                guard let fileURL = customFileURL(for: model) else { throw LanguageModelError.fileUnavailable }
                url = fileURL
            } else {
                guard downloader.isInstalled(model) else { throw LanguageModelError.notInstalled }
                url = downloader.localURL(for: model)
            }
            // One downloaded model in memory at a time.
            for (id, loaded) in engines where id != model.id {
                await loaded.unload()
                engines[id] = nil
            }
        }
        let engine = makeEngine(model, url)
        engines[model.id] = engine
        return engine
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        idleUnload = Task {
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            for engine in engines.values { await engine.unload() }
        }
    }

    /// Runs `work` after the jobs before it, and after any transcription
    /// when it needs a downloaded model.
    private func enqueue<T: Sendable>(
        usesDownloadedModel: Bool,
        _ work: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let previous = lastJob
        let job = Task { () throws -> T in
            await previous?.value
            try Task.checkCancellation()
            idleUnload?.cancel()
            if usesDownloadedModel {
                while isTranscribing() {
                    try await Task.sleep(for: .seconds(2))
                }
            }
            defer { scheduleIdleUnload() }
            return try await work()
        }
        lastJob = Task { _ = try? await job.value }
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }

    // MARK: - Titles

    /// A title for the transcript, from the title model.
    func suggestTitle(for recordingID: UUID, transcript: TranscriptText) async throws -> String {
        guard let model = titleModel else { throw LanguageModelError.notInstalled }
        titleJobs.insert(recordingID)
        defer { titleJobs.remove(recordingID) }
        return try await enqueue(usesDownloadedModel: model.runtime != .apple) { [self] in
            let engine = try await engine(for: model)
            let started = ContinuousClock.now
            let title = try await TitleSuggestion.title(for: transcript, using: engine)
            Logger.languageModels.notice("Title by \(model.id, privacy: .public) in \(ContinuousClock.now - started, privacy: .public)")
            return title
        }
    }

    // MARK: - Summaries

    /// The stored summary of a recording (read from disk once).
    func summary(for recordingID: UUID, in folder: URL) -> TranscriptSummary? {
        if let summary = summaries[recordingID] { return summary }
        let summary = TranscriptSummary.load(from: folder)
        if let summary { summaries[recordingID] = summary }
        if !checkedSummaryIDs.contains(recordingID) { checkedSummaryIDs.insert(recordingID) }
        return summary
    }

    /// Writes a summary and stores it in `folder` (the recording's folder,
    /// looked up when saving; nil = the recording is gone).
    func summarize(
        recordingID: UUID, transcript: TranscriptText, transcriptModifiedAt: Date, folder: @escaping @MainActor () -> URL?
    ) async throws {
        guard let model = summaryModel else { throw LanguageModelError.notInstalled }
        guard summaryJobs[recordingID] == nil else { return }
        summaryJobs[recordingID] = SummaryJob()
        defer {
            summaryJobs[recordingID] = nil
            summaryTasks[recordingID] = nil
        }
        let task = Task { [self] in
            let text = try await enqueue(usesDownloadedModel: true) { [self] in
                let engine = try await engine(for: model)
                let started = ContinuousClock.now
                let summary = try await SummaryGeneration.summary(of: transcript, using: engine) { progress in
                    Task { @MainActor in
                        guard self.summaryJobs[recordingID] != nil else { return }
                        self.summaryJobs[recordingID]?.progress = progress
                    }
                }
                Logger.languageModels.notice("Summary by \(model.id, privacy: .public) in \(ContinuousClock.now - started, privacy: .public)")
                return summary
            }
            // Cancelled at the last moment, e.g. because the recording was deleted.
            try Task.checkCancellation()
            guard let folder = folder() else { throw CancellationError() }
            let summary = TranscriptSummary(text: text, modelName: model.name, createdAt: .now, transcriptModifiedAt: transcriptModifiedAt)
            try summary.save(to: folder)
            summaries[recordingID] = summary
        }
        summaryTasks[recordingID] = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelSummary(for recordingID: UUID) {
        summaryTasks[recordingID]?.cancel()
    }

    /// Forgets the cached summary (the recording was deleted).
    func forgetSummary(for recordingID: UUID) {
        summaries[recordingID] = nil
        summaryTasks[recordingID]?.cancel()
    }
}
