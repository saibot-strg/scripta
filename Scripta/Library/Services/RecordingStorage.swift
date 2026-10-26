import Foundation
import os

/// File locations of recordings on disk.
///
/// Every recording owns a folder `<root>/<recording id>/` holding its audio
/// tracks. The database only stores file names relative to that folder.
struct RecordingStorage: Sendable {
    let rootURL: URL

    /// Default root inside the sandbox container:
    /// `~/Library/Containers/<bundle id>/Data/Library/Application Support/Recordings`.
    static var defaultRootURL: URL {
        URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    init(rootURL: URL = RecordingStorage.defaultRootURL) {
        self.rootURL = rootURL
    }

    func folderURL(for recordingID: UUID) -> URL {
        rootURL.appending(path: recordingID.uuidString, directoryHint: .isDirectory)
    }

    func fileURL(for recordingID: UUID, fileName: String) -> URL {
        folderURL(for: recordingID).appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Creates the recording's folder if needed and returns it.
    @discardableResult
    func makeFolder(for recordingID: UUID) throws -> URL {
        let url = folderURL(for: recordingID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Free space on the volume holding the recordings, if known.
    var availableCapacity: Int64? {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Deletes the recording's folder for good (leftovers of a failed start
    /// or import). A missing folder is not an error.
    func removeFolder(for recordingID: UUID) throws {
        let url = folderURL(for: recordingID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
        Logger.storage.info("Removed folder of recording \(recordingID, privacy: .public)")
    }

    /// Moves a deleted recording's folder to the Trash, named after its
    /// title, so a mistaken delete can be recovered in the Finder. Volumes
    /// without a Trash and temporary folders (tests, previews) delete it for good.
    func trashFolder(for recordingID: UUID, title: String) throws {
        var url = folderURL(for: recordingID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        guard !isTemporary else { return try removeFolder(for: recordingID) }
        let readable = rootURL.appending(path: Self.trashName(title: title, id: recordingID), directoryHint: .isDirectory)
        if (try? FileManager.default.moveItem(at: url, to: readable)) != nil {
            url = readable
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Logger.storage.info("Moved folder of recording \(recordingID, privacy: .public) to the Trash")
        } catch {
            Logger.storage.error("Could not move \(recordingID, privacy: .public) to the Trash: \(error.localizedDescription, privacy: .public)")
            try FileManager.default.removeItem(at: url)
        }
    }

    /// "Weekly 26.10. (3F2A9C1B)": the title, safe as a folder name, plus the
    /// start of the ID so two recordings with the same title don't collide.
    static func trashName(title: String, id: UUID) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(id.uuidString.prefix(8))
        return cleaned.isEmpty ? prefix : "\(cleaned) (\(prefix))"
    }

    private var isTemporary: Bool {
        rootURL.standardizedFileURL.path(percentEncoded: false)
            .hasPrefix(URL.temporaryDirectory.standardizedFileURL.path(percentEncoded: false))
    }
}
