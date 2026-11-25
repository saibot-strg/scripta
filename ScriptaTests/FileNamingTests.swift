import Foundation
import SwiftData
import Testing
@testable import Scripta

@Suite("Folder and file names from the title")
struct RecordingFileNamesTests {
    @Test("Titles become folder names the Finder shows as typed")
    func baseName() {
        #expect(RecordingFileNames.baseName(for: "Weekly 26.10.") == "Weekly 26.10.")
        #expect(RecordingFileNames.baseName(for: "Kunde/Projekt: Start") == "Kunde-Projekt- Start")
        #expect(RecordingFileNames.baseName(for: "Aufnahme 24.11.2026, 19:51") == "Aufnahme 24.11.2026, 19.51")
        #expect(RecordingFileNames.baseName(for: "Ziel:3") == "Ziel-3")
        #expect(RecordingFileNames.baseName(for: "Was nun?") == "Was nun?")
        #expect(RecordingFileNames.baseName(for: "  .versteckt ") == "versteckt")
        #expect(RecordingFileNames.baseName(for: "Zeile 1\nZeile 2\tEnde") == "Zeile 1 Zeile 2 Ende")
        #expect(RecordingFileNames.baseName(for: "   ") == nil)
        #expect(RecordingFileNames.baseName(for: "...") == nil)
    }

    @Test("FAT, exFAT and network volumes get only characters they accept")
    func strictBaseName() {
        #expect(RecordingFileNames.baseName(for: "Was nun?", strict: true) == "Was nun-")
        #expect(RecordingFileNames.baseName(for: #"A\B*C"D<E>F|G"#, strict: true) == "A-B-C-D-E-F-G")
        #expect(RecordingFileNames.baseName(for: "Weekly 26.10.", strict: true) == "Weekly 26.10")
    }

    @Test("Long titles are shortened to fit a file name")
    func longTitle() throws {
        let name = try #require(RecordingFileNames.baseName(for: String(repeating: "Ä", count: 200)))
        #expect(name.utf8.count <= RecordingFileNames.maximumBaseLength)
        #expect(name.allSatisfy { $0 == "Ä" })
    }

    @Test("Folders count up like Finder copies, files follow the folder")
    func names() {
        #expect(Array(RecordingFileNames.folderNames(for: "Weekly").prefix(3)) == ["Weekly", "Weekly 2", "Weekly 3"])
        #expect(RecordingFileNames.fileName(for: .primary, folderName: "Weekly 2", pathExtension: "m4a") == "Weekly 2.m4a")
        let microphone = RecordingFileNames.fileName(for: .microphone, folderName: "Weekly", pathExtension: "caf")
        let system = RecordingFileNames.fileName(for: .system, folderName: "Weekly", pathExtension: "caf")
        #expect(microphone == "Weekly (\(String(localized: "Mikrofon"))).caf")
        #expect(system == "Weekly (\(String(localized: "Systemaudio"))).caf")
    }
}

@MainActor
@Suite("Folders named after the title")
struct NamedFolderTests {
    let container = ModelContainerFactory.makeInMemory()
    let root = TestAudio.temporaryDirectory()

    var storage: RecordingStorage { RecordingStorage(rootURL: root) }
    var library: LibraryService { LibraryService(modelContext: container.mainContext, storage: storage) }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
    }

    private func folderContents(_ name: String) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: name).path(percentEncoded: false)))
    }

    /// A finished recording in its ID-named folder, as the recorder leaves it.
    private func finishedRecording(title: String, meeting: Bool = false) throws -> RecordingManifest {
        let manifest = meeting
            ? RecordingManifest(
                id: UUID(), title: title, createdAt: .now, source: .meeting, fileName: CaptureFormat.mixFileName,
                microphoneFileName: CaptureFormat.microphoneFileName, systemFileName: CaptureFormat.systemFileName
            )
            : RecordingManifest(id: UUID(), title: title, createdAt: .now, source: .microphone, fileName: CaptureFormat.fileName)
        try storage.makeFolder(for: manifest.id)
        try storage.writeManifest(manifest)
        for fileName in [manifest.fileName] + manifest.capturedFileNames {
            try Data(fileName.utf8).write(to: storage.fileURL(for: manifest.id, fileName: fileName))
        }
        return manifest
    }

    /// A recording from before named folders: `<id>/recording.m4a`.
    @discardableResult
    private func legacyRecording(title: String, createdAt: Date = .now) throws -> Recording {
        let recording = Recording(title: title, createdAt: createdAt, source: .microphone, status: .done)
        container.mainContext.insert(recording)
        recording.tracks.append(AudioTrack(role: .primary, fileName: "recording.m4a"))
        try container.mainContext.save()
        try storage.makeFolder(for: recording.id)
        try Data("audio".utf8).write(to: storage.fileURL(for: recording.id, fileName: "recording.m4a"))
        return recording
    }

    @Test("A new recording's folder and file are named after its title")
    func newRecording() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try finishedRecording(title: "Weekly 26.10.")
        let recording = try library.addRecording(manifest: manifest, duration: 1)

        #expect(recording.folderName == "Weekly 26.10.")
        #expect(recording.primaryTrack?.fileName == "Weekly 26.10..caf")
        #expect(try folderContents("Weekly 26.10.") == ["Weekly 26.10..caf"])
        #expect(!exists(manifest.id.uuidString))
        #expect(library.audioURL(for: recording)?.lastPathComponent == "Weekly 26.10..caf")
    }

    @Test("A meeting's three tracks are named after the title")
    func meeting() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try library.addRecording(manifest: try finishedRecording(title: "Kunde", meeting: true), duration: 1)

        let expected: Set<String> = ["Kunde.caf", "Kunde (\(String(localized: "Mikrofon"))).caf", "Kunde (\(String(localized: "Systemaudio"))).caf"]
        #expect(try folderContents("Kunde") == expected)
        #expect(Set(recording.tracks.map(\.fileName)) == expected)
        for role in TrackRole.allCases {
            #expect(library.audioURL(for: recording, role: role) != nil)
        }
    }

    @Test("Renaming renames folder and file; the same title gets a number")
    func rename() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try library.addRecording(manifest: try finishedRecording(title: "Weekly"), duration: 1)
        let second = try library.addRecording(manifest: try finishedRecording(title: "Weekly"), duration: 1)
        #expect(second.folderName == "Weekly 2")
        #expect(second.primaryTrack?.fileName == "Weekly 2.caf")

        try library.rename(first, to: "Planung Q1/Q2")
        #expect(first.folderName == "Planung Q1-Q2")
        #expect(try folderContents("Planung Q1-Q2") == ["Planung Q1-Q2.caf"])
        #expect(!exists("Weekly"))

        // The plain name is free again: the next rename takes it.
        try library.rename(second, to: "weekly")
        try library.rename(second, to: "Weekly")
        #expect(second.folderName == "Weekly")
        #expect(try folderContents("Weekly") == ["Weekly.caf"])
        #expect(library.audioURL(for: second) != nil)
    }

    @Test("Only the case changes: the folder is renamed, not numbered")
    func caseOnly() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try library.addRecording(manifest: try finishedRecording(title: "weekly"), duration: 1)
        try library.rename(recording, to: "Weekly")
        #expect(recording.folderName == "Weekly")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["Weekly"])
        #expect(try folderContents("Weekly") == ["Weekly.caf"])
    }

    @Test("Existing recordings are renamed at launch, oldest first; other files stay")
    func legacy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let newer = try legacyRecording(title: "Weekly", createdAt: .now)
        let older = try legacyRecording(title: "Weekly", createdAt: .now.addingTimeInterval(-3600))
        try Data("{}".utf8).write(to: storage.folderURL(for: older.id).appending(path: TranscriptSummary.fileName))
        let model = AppModel(library: library)

        await model.nameFilesAfterTitles()

        #expect(older.folderName == "Weekly")
        #expect(newer.folderName == "Weekly 2")
        #expect(try folderContents("Weekly") == ["Weekly.m4a", TranscriptSummary.fileName])
        #expect(try folderContents("Weekly 2") == ["Weekly 2.m4a"])
        #expect(model.summaryFolder(for: older)?.lastPathComponent == "Weekly")
        // A second run changes nothing.
        await model.nameFilesAfterTitles()
        #expect(older.folderName == "Weekly" && newer.folderName == "Weekly 2")
    }

    @Test("While a job uses the files, the rename waits")
    func busy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try legacyRecording(title: "Alt")
        let library = library
        recording.status = .running
        try library.rename(recording, to: "Neu")
        #expect(recording.title == "Neu")
        #expect(recording.folderName == nil)

        recording.status = .done
        var encoding = true
        library.isUsingFiles = { _ in encoding }
        library.nameFiles(of: recording)
        #expect(recording.folderName == nil)

        encoding = false
        library.nameFiles(of: recording)
        #expect(recording.folderName == "Neu")
        #expect(try folderContents("Neu") == ["Neu.m4a"])
    }

    @Test("A missing folder (disk not connected) is left alone")
    func missingFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try legacyRecording(title: "Extern")
        try FileManager.default.removeItem(at: storage.folderURL(for: recording.id))
        library.nameFiles(of: recording)
        #expect(recording.folderName == nil)
        #expect(recording.primaryTrack?.fileName == "recording.m4a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
    }

    @Test("A recording on a disk that isn't connected never touches a same-named folder here")
    func unreachableLocation() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library
        let here = try library.addRecording(manifest: try finishedRecording(title: "Weekly"), duration: 1)
        let away = Recording(title: "Weekly", source: .microphone, status: .done)
        away.storageRootBookmark = Data("no longer resolvable".utf8)
        away.folderName = "Weekly"
        container.mainContext.insert(away)
        away.tracks.append(AudioTrack(role: .primary, fileName: "Weekly.caf"))
        try container.mainContext.save()

        #expect(library.audioURL(for: away) == nil)
        try library.rename(away, to: "Daily")
        #expect(away.folderName == "Weekly")
        try library.delete(away)

        #expect(try folderContents("Weekly") == ["Weekly.caf"])
        #expect(library.audioURL(for: here) != nil)
    }

    @Test("If a file can't be renamed, everything keeps its old name")
    func rollback() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try legacyRecording(title: "Konflikt")
        // A stray file already has the audio file's new name.
        try Data("fremd".utf8).write(to: storage.fileURL(for: recording.id, fileName: "Konflikt.m4a"))

        library.nameFiles(of: recording)

        #expect(recording.folderName == nil)
        #expect(recording.primaryTrack?.fileName == "recording.m4a")
        #expect(try folderContents(recording.id.uuidString) == ["recording.m4a", "Konflikt.m4a"])
        #expect(!exists("Konflikt"))
        #expect(library.audioURL(for: recording) != nil)
    }

    @Test("A deleted recording's named folder is removed")
    func delete() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = try library.addRecording(manifest: try finishedRecording(title: "Weg"), duration: 1)
        try library.delete(recording)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
    }

    @Test("Undoing a rename gives folder and file their old name back")
    func undo() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(library: library)
        let editMenu = UndoManager()
        editMenu.groupsByEvent = false
        model.attachUndoManager(editMenu)
        let recording = try model.library.addRecording(manifest: try finishedRecording(title: "Vorher"), duration: 1)

        model.rename(recording, to: "Nachher")
        #expect(try folderContents("Nachher") == ["Nachher.caf"])
        editMenu.undo()
        #expect(recording.folderName == "Vorher")
        #expect(try folderContents("Vorher") == ["Vorher.caf"])
        #expect(!exists("Nachher"))
    }
}

@MainActor
@Suite("Library migration to named folders")
struct NamedFolderMigrationTests {
    @Test("A version 2 library opens as version 3; recordings keep their ID folders until renamed")
    func v2ToV3() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Library.store")

        do {
            let schema = Schema(versionedSchema: LibrarySchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            let recording = LibrarySchemaV2.Recording(title: "Weekly", sourceRaw: "meeting", statusRaw: "done")
            context.insert(recording)
            recording.tracks.append(LibrarySchemaV2.AudioTrack(roleRaw: "primary", fileName: "mix.m4a"))
            let filed = LibrarySchemaV2.Folder(name: "Projekt")
            context.insert(filed)
            recording.folder = filed
            try context.save()
        }

        let container = try ModelContainerFactory.makeOnDisk(at: url)
        let recording = try #require(try container.mainContext.fetch(FetchDescriptor<Recording>()).first)
        #expect(recording.title == "Weekly")
        #expect(recording.tracks.map(\.fileName) == ["mix.m4a"])
        #expect(recording.folder?.name == "Projekt")
        #expect(recording.folderName == nil)
    }
}

@Suite("Backup before naming folders")
struct LibraryBackupTests {
    @Test("The library and the recordings are copied once, before anything changes")
    func backup() throws {
        let support = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "LibraryBackupTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recordings = support.appending(path: "Recordings", directoryHint: .isDirectory)
        let folder = recordings.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: folder.appending(path: "recording.m4a"))
        try Data("store".utf8).write(to: support.appending(path: "Library.store"))
        try Data("wal".utf8).write(to: support.appending(path: "Library.store-wal"))

        #expect(LibraryBackup.makeIfNeeded(defaults: defaults, supportURL: support, recordingsURL: recordings))

        let backup = support.appending(path: LibraryBackup.folderName, directoryHint: .isDirectory)
        #expect(try Data(contentsOf: backup.appending(path: "Library.store")) == Data("store".utf8))
        #expect(try Data(contentsOf: backup.appending(path: "Library.store-wal")) == Data("wal".utf8))
        let copied = backup.appending(path: "Recordings/\(folder.lastPathComponent)/recording.m4a")
        #expect(try Data(contentsOf: copied) == Data("audio".utf8))
        #expect(LibraryBackup.isDone(defaults: defaults))

        // Only once: later changes don't touch the backup.
        try FileManager.default.removeItem(at: folder)
        #expect(LibraryBackup.makeIfNeeded(defaults: defaults, supportURL: support, recordingsURL: recordings))
        #expect(FileManager.default.fileExists(atPath: copied.path(percentEncoded: false)))
    }

    @Test("A new installation needs no backup")
    func newInstallation() throws {
        let support = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "LibraryBackupTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LibraryBackup.makeIfNeeded(defaults: defaults, supportURL: support, recordingsURL: support.appending(path: "Recordings")))
        #expect(LibraryBackup.isDone(defaults: defaults))
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.path(percentEncoded: false)).isEmpty)
    }
}

@MainActor
@Suite("Moving recordings to a new location")
struct MoveRecordingsTests {
    let container = ModelContainerFactory.makeInMemory()
    let oldRoot = TestAudio.temporaryDirectory()
    let newRoot = TestAudio.temporaryDirectory()
    let suite = "MoveRecordingsTests-\(UUID().uuidString)"

    private func cleanUp() {
        try? FileManager.default.removeItem(at: oldRoot)
        try? FileManager.default.removeItem(at: newRoot)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func contents(_ url: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)))
    }

    /// A recording in the default location, as before named folders: `<id>/recording.m4a`.
    private func legacyRecording(_ title: String, in library: LibraryService, minutesAgo: Double) throws -> Recording {
        let recording = Recording(title: title, createdAt: .now.addingTimeInterval(-minutesAgo * 60), source: .microphone, status: .done)
        container.mainContext.insert(recording)
        recording.tracks.append(AudioTrack(role: .primary, fileName: "recording.m4a"))
        try container.mainContext.save()
        let storage = RecordingStorage(rootURL: oldRoot)
        try storage.makeFolder(for: recording.id)
        try Data(title.utf8).write(to: storage.fileURL(for: recording.id, fileName: "recording.m4a"))
        return recording
    }

    @Test("All recordings move, named after their titles; nothing is copied, lost or overwritten")
    func moveAll() async throws {
        defer { cleanUp() }
        let locations = StorageLocations(defaults: try #require(UserDefaults(suiteName: suite)), defaultStorage: RecordingStorage(rootURL: oldRoot))
        let library = LibraryService(modelContext: container.mainContext, locations: locations)
        let weekly = try legacyRecording("Weekly", in: library, minutesAgo: 10)
        let note = try legacyRecording("Notiz 19:51", in: library, minutesAgo: 5)
        try Data("{}".utf8).write(to: oldRoot.appending(path: "\(note.id.uuidString)/\(TranscriptSummary.fileName)"))
        // Something of the user's own already has the name "Weekly" there.
        let foreign = newRoot.appending(path: "Weekly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("privat".utf8).write(to: foreign.appending(path: "notizen.txt"))

        try locations.use(newRoot)
        let model = AppModel(library: library)
        #expect(library.recordingsElsewhere().count == 2)

        let result = await model.moveRecordingsToCurrentLocation()

        #expect(result.moved == 2 && result.remaining == 0)
        #expect(try contents(oldRoot).isEmpty)
        #expect(try contents(newRoot) == ["Weekly", "Weekly 2", "Notiz 19.51"])
        #expect(try contents(foreign) == ["notizen.txt"])
        #expect(try contents(newRoot.appending(path: "Weekly 2")) == ["Weekly 2.m4a"])
        #expect(try contents(newRoot.appending(path: "Notiz 19.51")) == ["Notiz 19.51.m4a", TranscriptSummary.fileName])
        #expect(try Data(contentsOf: try #require(library.audioURL(for: weekly))) == Data("Weekly".utf8))
        #expect(try Data(contentsOf: try #require(library.audioURL(for: note))) == Data("Notiz 19:51".utf8))
        #expect(weekly.storageRootBookmark == locations.currentBookmark)
        #expect(library.recordingsElsewhere().isEmpty)
        // New recordings go there too.
        #expect(library.storage.rootURL.standardizedFileURL == newRoot.standardizedFileURL)
    }

    @Test("A recording that is being transcribed stays and is counted")
    func busyStays() async throws {
        defer { cleanUp() }
        let locations = StorageLocations(defaults: try #require(UserDefaults(suiteName: suite)), defaultStorage: RecordingStorage(rootURL: oldRoot))
        let library = LibraryService(modelContext: container.mainContext, locations: locations)
        let busy = try legacyRecording("Läuft", in: library, minutesAgo: 1)
        busy.status = .running
        try locations.use(newRoot)

        let result = await AppModel(library: library).moveRecordingsToCurrentLocation()

        #expect(result.moved == 0 && result.remaining == 1)
        #expect(try contents(oldRoot) == [busy.id.uuidString])
        #expect(library.audioURL(for: busy) != nil)
    }
}
