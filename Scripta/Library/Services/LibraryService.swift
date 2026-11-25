import Foundation
import SwiftData
import os

/// Mutating operations on the library. Runs on the main actor because it
/// works with the container's `mainContext`, which also drives the UI.
@MainActor
final class LibraryService {
    let modelContext: ModelContext
    let locations: StorageLocations

    /// Storage for new recordings (the chosen location).
    var storage: RecordingStorage { locations.current }

    init(modelContext: ModelContext, locations: StorageLocations) {
        self.modelContext = modelContext
        self.locations = locations
    }

    /// Fixed storage, for tests and previews.
    convenience init(modelContext: ModelContext, storage: RecordingStorage = RecordingStorage()) {
        self.init(modelContext: modelContext, locations: StorageLocations(fixed: storage))
    }

    /// Where a recording's files are (its location at recording time); nil if
    /// that location can't be reached (external disk not connected).
    func storage(for recording: Recording) -> RecordingStorage? {
        locations.storage(forBookmark: recording.storageRootBookmark)
    }

    /// Adds a finished recording whose audio files are already on disk, then
    /// removes its manifest. Meetings get their microphone and system tracks too.
    /// - Parameter rootBookmark: The storage location the files were written to.
    @discardableResult
    func addRecording(
        manifest: RecordingManifest,
        duration: TimeInterval,
        title: String? = nil,
        rootBookmark: Data? = nil
    ) throws(LibraryError) -> Recording {
        let storage = locations.storage(forBookmark: rootBookmark)
        let recording = Recording(
            id: manifest.id,
            title: title ?? manifest.title,
            createdAt: manifest.createdAt,
            duration: duration,
            source: manifest.source
        )
        recording.storageRootBookmark = rootBookmark
        modelContext.insert(recording)
        recording.tracks.append(AudioTrack(role: .primary, fileName: manifest.fileName, duration: duration))
        let separateTracks: [(TrackRole, String?)] = [(.microphone, manifest.microphoneFileName), (.system, manifest.systemFileName)]
        for case let (role, fileName?) in separateTracks {
            let trackDuration = storage.flatMap { AudioFileInfo.duration(of: $0.fileURL(for: manifest.id, fileName: fileName)) }
            recording.tracks.append(AudioTrack(role: role, fileName: fileName, duration: trackDuration ?? duration))
        }
        try save()
        storage?.removeManifest(for: manifest.id)
        nameFiles(of: recording)
        return recording
    }

    func recording(withID id: UUID) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// URL of the playable audio file, if it exists on disk.
    func audioURL(for recording: Recording) -> URL? {
        audioURL(for: recording, role: .primary)
    }

    /// URL of a track's file, if it exists on disk.
    func audioURL(for recording: Recording, role: TrackRole) -> URL? {
        guard let track = recording.tracks.first(where: { $0.role == role }),
              let url = fileURL(for: recording, fileName: track.fileName) else { return nil }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The recording's folder on disk (named after its title, or its ID);
    /// nil if its location can't be reached.
    func folderURL(for recording: Recording) -> URL? {
        storage(for: recording)?.folderURL(for: recording.id, named: recording.folderName)
    }

    func fileURL(for recording: Recording, fileName: String) -> URL? {
        folderURL(for: recording)?.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Points a track to a new file (e.g. after AAC encoding) and deletes the old one.
    func replaceFile(of track: AudioTrack, in recording: Recording, with fileName: String) throws(LibraryError) {
        guard track.fileName != fileName else { return }
        let oldURL = fileURL(for: recording, fileName: track.fileName)
        track.fileName = fileName
        try save()
        if let oldURL { try? FileManager.default.removeItem(at: oldURL) }
    }

    /// Renames a recording and its folder and files. Empty titles are ignored.
    func rename(_ recording: Recording, to newTitle: String) throws(LibraryError) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != recording.title else { return }
        recording.title = title
        try save()
        nameFiles(of: recording)
    }

    // MARK: - Folder and file names

    /// Recordings whose files a job outside the library reads or writes right
    /// now (AAC encoding); set by the app. A running transcription is known
    /// from the status.
    var isUsingFiles: (UUID) -> Bool = { _ in false }

    /// Names the recording's folder and audio files after its title
    /// (`Weekly/Weekly.m4a`, see `RecordingFileNames`).
    ///
    /// Waits while a transcription or encoding uses the files (they are
    /// opened by path more than once): call it again when the job ends. Does
    /// nothing if the folder is missing (e.g. external disk not connected).
    /// If a step fails, everything keeps its old name.
    func nameFiles(of recording: Recording) {
        guard !isBusy(recording), let storage = storage(for: recording) else { return }
        relocate(recording, from: storage, to: storage, bookmark: recording.storageRootBookmark)
    }

    /// Moves the recording's folder to another location (`bookmark` is the
    /// target's, nil = default), naming it after the title on the way. Same
    /// volume: a rename; another volume: copied, then the original removed.
    /// - Returns: Whether the recording is in `target` now. False while a job
    ///   uses its files, if its location can't be reached or if a step failed
    ///   (then everything stays where it was).
    @discardableResult
    func moveFiles(of recording: Recording, to target: RecordingStorage, bookmark: Data?) -> Bool {
        guard !isBusy(recording), let source = storage(for: recording) else { return false }
        return relocate(recording, from: source, to: target, bookmark: bookmark)
    }

    /// Recordings stored somewhere other than the location for new recordings.
    func recordingsElsewhere() -> [Recording] {
        let all = (try? modelContext.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { $0.storageRootBookmark != locations.currentBookmark }
    }

    private func isBusy(_ recording: Recording) -> Bool {
        recording.status == .running || isUsingFiles(recording.id)
    }

    @discardableResult
    private func relocate(_ recording: Recording, from source: RecordingStorage, to target: RecordingStorage, bookmark: Data?) -> Bool {
        let fileManager = FileManager.default
        let folder = source.folderURL(for: recording.id, named: recording.folderName)
        guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return false }
        try? fileManager.createDirectory(at: target.rootURL, withIntermediateDirectories: true)
        let sameRoot = source.rootURL.standardizedFileURL.path(percentEncoded: false) == target.rootURL.standardizedFileURL.path(percentEncoded: false)
            || FileMoves.isSameItem(source.rootURL, target.rootURL)
        // A title without usable characters keeps its folder name, also when moving.
        guard let baseName = RecordingFileNames.baseName(for: recording.title, strict: target.needsStrictNames)
                ?? (sameRoot ? nil : folder.lastPathComponent),
              let folderName = target.folderName(for: baseName, keeping: sameRoot ? folder : nil) else { return false }

        let destination = target.folderURL(for: recording.id, named: folderName)
        var moves = FileMoves()
        var fileNames: [(AudioTrack, String)] = []
        do {
            if !sameRoot || folderName != folder.lastPathComponent {
                try moves.move(folder, to: destination)
            }
            for track in recording.tracks {
                let fileName = RecordingFileNames.fileName(
                    for: track.role, folderName: folderName, pathExtension: (track.fileName as NSString).pathExtension
                )
                let file = destination.appending(path: track.fileName, directoryHint: .notDirectory)
                guard fileName != track.fileName, fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
                try moves.move(file, to: destination.appending(path: fileName, directoryHint: .notDirectory))
                fileNames.append((track, fileName))
            }
        } catch {
            moves.revert()
            Logger.storage.error("Could not rename or move files of \(recording.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        let isUnchanged = recording.folderName == folderName && fileNames.isEmpty && recording.storageRootBookmark == bookmark
        guard !isUnchanged else { return true }
        recording.folderName = folderName
        recording.storageRootBookmark = bookmark
        for (track, fileName) in fileNames {
            track.fileName = fileName
        }
        do {
            try save()
            Logger.storage.info("Files of \(recording.id, privacy: .public) named after the title\(sameRoot ? "" : " and moved", privacy: .public)")
            return true
        } catch {
            // The context was rolled back to the old names.
            moves.revert()
            return false
        }
    }

    /// `nameFiles(of:)` for the recording, if it still exists.
    func nameFiles(ofRecordingWithID id: UUID) {
        guard let recording = recording(withID: id) else { return }
        nameFiles(of: recording)
    }

    /// Deletes a recording and its transcript; its audio files go to the Trash.
    func delete(_ recording: Recording) throws(LibraryError) {
        let id = recording.id
        let title = recording.title
        let folderName = recording.folderName
        let storage = storage(for: recording)
        modelContext.delete(recording)
        try save()
        guard let storage else {
            Logger.storage.notice("Files of \(id, privacy: .public) stay in their unreachable location")
            return
        }
        // Files go last: if saving fails, the recording stays intact and playable.
        do {
            try storage.trashFolder(for: id, named: folderName, title: title)
        } catch {
            Logger.storage.error("Could not remove files of \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .fileRemovalFailed(underlying: error)
        }
    }

    // MARK: - Folders

    func transcript(withID id: UUID) -> Transcript? {
        var descriptor = FetchDescriptor<Transcript>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func segment(withID id: UUID) -> TranscriptSegment? {
        var descriptor = FetchDescriptor<TranscriptSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func folder(withID id: UUID) -> Folder? {
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    /// `id` brings back a folder that was deleted (undo).
    @discardableResult
    func createFolder(named name: String, id: UUID? = nil) throws(LibraryError) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(name: trimmed.isEmpty ? String(localized: "Neuer Ordner") : trimmed)
        if let id { folder.id = id }
        modelContext.insert(folder)
        try save()
        return folder
    }

    /// Empty names are ignored.
    func rename(_ folder: Folder, to newName: String) throws(LibraryError) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return }
        folder.name = name
        try save()
    }

    /// Deletes the folder; its recordings stay in the library.
    func delete(_ folder: Folder) throws(LibraryError) {
        modelContext.delete(folder)
        try save()
    }

    /// Files recordings in a folder (nil takes them out of their folder).
    func move(_ recordings: [Recording], to folder: Folder?) throws(LibraryError) {
        for recording in recordings {
            recording.folder = folder
        }
        try save()
    }

    func save() throws(LibraryError) {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            Logger.library.error("Save failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            throw .saveFailed(underlying: error)
        }
    }

    #if DEBUG
    /// Inserts dummy recordings for UI development.
    func insertSampleData() throws(LibraryError) {
        SampleData.insert(into: modelContext)
        try save()
    }

    /// Removes all recordings (debug builds only).
    func deleteAll() throws(LibraryError) {
        let recordings = (try? modelContext.fetch(FetchDescriptor<Recording>())) ?? []
        for recording in recordings {
            try delete(recording)
        }
    }
    #endif
}
