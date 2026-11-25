import Foundation
import os

/// A summary written by a language model, stored as `summary.json` in the
/// recording's folder: it moves and goes to the Trash with the audio, and
/// the library database needs no new fields.
struct TranscriptSummary: Codable, Equatable, Sendable {
    /// Markdown: "## Kurzfassung", bullet lists …
    var text: String
    var modelName: String
    var createdAt: Date
    /// The transcript's `modifiedAt` when the summary was written.
    var transcriptModifiedAt: Date

    static let fileName = "summary.json"

    /// True if the transcript was corrected or transcribed again since.
    func isOutdated(for transcript: Transcript?) -> Bool {
        guard let transcript else { return true }
        return transcript.modifiedAt.timeIntervalSince(transcriptModifiedAt) > 1
    }

    static func url(in folder: URL) -> URL {
        folder.appending(path: fileName, directoryHint: .notDirectory)
    }

    static func load(from folder: URL) -> TranscriptSummary? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        do {
            return try decoder.decode(TranscriptSummary.self, from: data)
        } catch {
            Logger.languageModels.error("Unreadable summary: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: Self.url(in: folder), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
