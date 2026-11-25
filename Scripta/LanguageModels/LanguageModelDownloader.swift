import Foundation
import Synchronization
import os

/// Where downloaded models live and how they get there: straight from
/// Hugging Face into `Application Support/LanguageModels/<model id>/`.
/// A download goes to `<model id>.partial` first, so a model folder only
/// exists once every file is complete.
struct LanguageModelDownloader: Sendable {
    let rootURL: URL
    var session: URLSession = .shared

    static var defaultRootURL: URL {
        URL.applicationSupportDirectory.appending(path: "LanguageModels", directoryHint: .isDirectory)
    }

    init(rootURL: URL = LanguageModelDownloader.defaultRootURL) {
        self.rootURL = rootURL
    }

    func directory(for model: LanguageModelDescriptor) -> URL {
        rootURL.appending(path: model.id, directoryHint: .isDirectory)
    }

    /// The folder (MLX) or file (GGUF) a model is loaded from.
    func localURL(for model: LanguageModelDescriptor) -> URL {
        switch model.runtime {
        case .gguf: directory(for: model).appending(path: model.fileName ?? "", directoryHint: .notDirectory)
        case .mlx, .apple: directory(for: model)
        }
    }

    func isInstalled(_ model: LanguageModelDescriptor) -> Bool {
        guard model.runtime != .apple else { return true }
        let marker = model.runtime == .mlx ? directory(for: model).appending(path: "config.json") : localURL(for: model)
        return FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
    }

    func installedSize(of model: LanguageModelDescriptor) -> Int64? {
        isInstalled(model) && model.runtime != .apple ? directory(for: model).directorySize : nil
    }

    func delete(_ model: LanguageModelDescriptor) throws {
        for url in [directory(for: model), partialDirectory(for: model)]
        where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Download

    struct RemoteFile: Decodable, Equatable, Sendable {
        let rfilename: String
        let size: Int64?
    }

    /// Downloads every file of the model. `progress` gets 0...1.
    func download(_ model: LanguageModelDescriptor, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let repository = model.repository else { return }
        let files: [RemoteFile] = if let fileName = model.fileName {
            [RemoteFile(rfilename: fileName, size: model.downloadSize)]
        } else {
            try await listFiles(in: repository)
        }
        let total = max(files.reduce(0) { $0 + ($1.size ?? 0) }, 1)

        let partial = partialDirectory(for: model)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let done = completed
            let destination = partial.appending(path: file.rfilename, directoryHint: .notDirectory)
            try await download(file.rfilename, from: repository, to: destination) { written in
                progress(min(Double(done + written) / Double(total), 1))
            }
            if let size = file.size, let actual = destination.fileSize, actual != size {
                throw URLError(.cannotDecodeContentData)
            }
            completed += file.size ?? 0
        }

        let final = directory(for: model)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partial, to: final)
        Logger.languageModels.notice("Downloaded \(model.id, privacy: .public)")
    }

    /// The files of a repository, without the model card and git files.
    func listFiles(in repository: String) async throws -> [RemoteFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repository)?blobs=true") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        try Self.check(response)
        struct Listing: Decodable { let siblings: [RemoteFile] }
        return try JSONDecoder().decode(Listing.self, from: data).siblings.filter { Self.isNeeded($0.rfilename) }
    }

    static func isNeeded(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return !name.hasPrefix(".") && !name.hasSuffix(".md") && !name.hasSuffix(".png") && !name.hasSuffix(".jpg")
    }

    private func download(
        _ fileName: String,
        from repository: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let path = fileName.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
        guard let url = URL(string: "https://huggingface.co/\(repository)/resolve/main/\(path.joined(separator: "/"))") else {
            throw URLError(.badURL)
        }
        let (temporary, response) = try await session.download(from: url, delegate: DownloadProgress(report: progress))
        try Self.check(response)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func partialDirectory(for model: LanguageModelDescriptor) -> URL {
        rootURL.appending(path: model.id + ".partial", directoryHint: .isDirectory)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}

/// Reports the bytes received so far of one download, every few MB.
///
/// The async `download(from:delegate:)` never calls the download delegate's
/// `didWriteData`, and the task's `progress` only changes at the start and
/// the end (measured), so this watches the task's received bytes.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let report: @Sendable (Int64) -> Void
    private let observation = Mutex<NSKeyValueObservation?>(nil)
    private let lastReported = Mutex<Int64>(0)
    private static let step: Int64 = 8 * 1024 * 1024

    init(report: @escaping @Sendable (Int64) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let watch = task.observe(\.countOfBytesReceived) { [weak self] task, _ in
            self?.received(task.countOfBytesReceived, of: task.countOfBytesExpectedToReceive)
        }
        observation.withLock { $0 = watch }
    }

    private func received(_ bytes: Int64, of total: Int64) {
        let isDue = lastReported.withLock { last in
            guard bytes - last >= Self.step || bytes == total else { return false }
            last = bytes
            return true
        }
        if isDue { report(bytes) }
    }
}

private extension URL {
    var fileSize: Int64? {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}
