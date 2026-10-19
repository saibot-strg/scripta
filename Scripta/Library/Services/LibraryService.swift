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

    /// Where a recording's files are (its location at recording time).
    func storage(for recording: Recording) -> RecordingStorage {
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
            let url = storage.fileURL(for: manifest.id, fileName: fileName)
            recording.tracks.append(AudioTrack(role: role, fileName: fileName, duration: AudioFileInfo.duration(of: url) ?? duration))
        }
        try save()
        storage.removeManifest(for: manifest.id)
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
        guard let track = recording.tracks.first(where: { $0.role == role }) else { return nil }
        let url = storage(for: recording).fileURL(for: recording.id, fileName: track.fileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Points a track to a new file (e.g. after AAC encoding) and deletes the old one.
    func replaceFile(of track: AudioTrack, in recording: Recording, with fileName: String) throws(LibraryError) {
        guard track.fileName != fileName else { return }
        let oldURL = storage(for: recording).fileURL(for: recording.id, fileName: track.fileName)
        track.fileName = fileName
        try save()
        try? FileManager.default.removeItem(at: oldURL)
    }

    /// Renames a recording. Empty titles are ignored.
    func rename(_ recording: Recording, to newTitle: String) throws(LibraryError) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != recording.title else { return }
        recording.title = title
        try save()
    }

    /// Deletes a recording, its transcript and its audio files.
    func delete(_ recording: Recording) throws(LibraryError) {
        let id = recording.id
        let storage = storage(for: recording)
        modelContext.delete(recording)
        try save()
        // Files go last: if saving fails, the recording stays intact and playable.
        do {
            try storage.removeFolder(for: id)
        } catch {
            Logger.storage.error("Could not remove files of \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .fileRemovalFailed(underlying: error)
        }
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
