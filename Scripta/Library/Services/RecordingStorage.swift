import Foundation
import os

/// File locations of recordings on disk.
///
/// Every recording owns a folder below the root holding its audio tracks:
/// `<root>/<recording id>/` while recording, `<root>/<title>/` once it is in
/// the library (see `RecordingFileNames`). The database stores the folder
/// name and file names relative to that folder.
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

    /// The folder named after the ID: used while recording and by recordings
    /// whose folder was not renamed yet.
    func folderURL(for recordingID: UUID) -> URL {
        folderURL(for: recordingID, named: nil)
    }

    /// A recording's folder: `folderName`, or its ID if nil.
    func folderURL(for recordingID: UUID, named folderName: String?) -> URL {
        rootURL.appending(path: folderName ?? recordingID.uuidString, directoryHint: .isDirectory)
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

    /// Moves a deleted recording's folder to the Trash, so a mistaken delete
    /// can be recovered in the Finder. A folder still named after the ID gets
    /// the title first. Volumes without a Trash and temporary folders (tests,
    /// previews) delete it for good.
    func trashFolder(for recordingID: UUID, named folderName: String?, title: String) throws {
        var url = folderURL(for: recordingID, named: folderName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        guard !isTemporary else {
            try FileManager.default.removeItem(at: url)
            Logger.storage.info("Removed folder of recording \(recordingID, privacy: .public)")
            return
        }
        if folderName == nil {
            let readable = rootURL.appending(path: Self.trashName(title: title, id: recordingID), directoryHint: .isDirectory)
            if (try? FileManager.default.moveItem(at: url, to: readable)) != nil {
                url = readable
            }
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

    // MARK: - Names from the title

    /// True on volumes that reject `\ * ? " < > |` in names (FAT, exFAT,
    /// network volumes); APFS and HFS+ only reject "/" and ":".
    var needsStrictNames: Bool {
        guard let type = try? rootURL.resourceValues(forKeys: [.volumeTypeNameKey]).volumeTypeName else { return false }
        return !["apfs", "hfs"].contains(type.lowercased())
    }

    /// The first of "Weekly", "Weekly 2", … that is free or already names
    /// `folder` (also when it differs only in case on a case-insensitive
    /// volume). `folder` is nil when a folder comes from another location.
    func folderName(for baseName: String, keeping folder: URL?) -> String? {
        for name in RecordingFileNames.folderNames(for: baseName) {
            if let folder, name == folder.lastPathComponent { return name }
            let candidate = rootURL.appending(path: name, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else { return name }
            if let folder, FileMoves.isSameItem(candidate, folder) { return name }
        }
        return nil
    }

    private var isTemporary: Bool {
        rootURL.standardizedFileURL.path(percentEncoded: false)
            .hasPrefix(URL.temporaryDirectory.standardizedFileURL.path(percentEncoded: false))
    }
}

/// Moves files and folders and can put them all back, so a rename that
/// fails halfway leaves everything as it was.
struct FileMoves {
    private var done: [(source: URL, destination: URL)] = []

    mutating func move(_ source: URL, to destination: URL) throws {
        try Self.move(source, to: destination)
        done.append((source, destination))
    }

    /// Undoes the moves, last first.
    func revert() {
        for move in done.reversed() {
            do {
                try Self.move(move.destination, to: move.source)
            } catch {
                Logger.storage.error("Could not move back \(move.destination.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Never replaces another item. A change of case only (the volume sees
    /// the same item) goes through a temporary name.
    private static func move(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            return try fileManager.moveItem(at: source, to: destination)
        }
        guard isSameItem(source, destination) else { throw CocoaError(.fileWriteFileExists) }
        let temporary = source.deletingLastPathComponent().appending(path: ".scripta-renaming-\(UUID().uuidString)")
        try fileManager.moveItem(at: source, to: temporary)
        do {
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.moveItem(at: temporary, to: source)
            throw error
        }
    }

    static func isSameItem(_ first: URL, _ second: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: key).fileResourceIdentifier,
              let b = try? second.resourceValues(forKeys: key).fileResourceIdentifier else { return false }
        return a.isEqual(b)
    }
}
