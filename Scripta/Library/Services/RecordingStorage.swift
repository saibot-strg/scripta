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

    /// Removes the recording's folder. A missing folder is not an error.
    func removeFolder(for recordingID: UUID) throws {
        let url = folderURL(for: recordingID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
        Logger.storage.info("Removed folder of recording \(recordingID, privacy: .public)")
    }
}
