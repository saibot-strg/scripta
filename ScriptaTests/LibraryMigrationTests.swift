import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Library migration")
struct LibraryMigrationTests {
    @Test("A version 1 library opens as version 2 with all its data")
    func v1ToV2() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Library.store")

        do {
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            let recording = LibrarySchemaV1.Recording(title: "Altes Meeting", sourceRaw: "meeting", statusRaw: "done")
            context.insert(recording)
            recording.tracks.append(LibrarySchemaV1.AudioTrack(roleRaw: "primary", fileName: "mix.m4a"))
            let transcript = LibrarySchemaV1.Transcript(engineIdentifier: "parakeet-ultra")
            recording.transcript = transcript
            let speaker = LibrarySchemaV1.SpeakerLabel(roleRaw: "diarized", number: 1)
            speaker.customName = "Max"
            transcript.speakers.append(speaker)
            let segment = LibrarySchemaV1.TranscriptSegment(index: 0, start: 0, end: 2, text: "Hallo zusammen.")
            transcript.segments.append(segment)
            segment.speaker = speaker
            try context.save()
        }

        let container = try ModelContainerFactory.makeOnDisk(at: url)
        let context = container.mainContext
        let recording = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(recording.title == "Altes Meeting")
        #expect(recording.tracks.map(\.fileName) == ["mix.m4a"])
        #expect(recording.transcript?.segments.first?.speaker?.displayName == "Max")
        #expect(recording.folder == nil)

        // Folders work in the migrated store.
        let filed = Folder(name: "Projekt")
        context.insert(filed)
        recording.folder = filed
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Folder>()).first?.recordings.count == 1)
    }
}

@MainActor
@Suite("Clock time")
struct ClockTimeTests {
    @Test("Passages of recordings made in Scripta know their clock time, imports don't")
    func spokenAt() throws {
        let container = try TestStore.makeContainer()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for (source, expected) in [(RecordingSource.meeting, start.addingTimeInterval(90)), (.importedFile, nil)] {
            let recording = Recording(title: "T", createdAt: start, source: source)
            container.mainContext.insert(recording)
            let transcript = Transcript(engineIdentifier: "test")
            recording.transcript = transcript
            let segment = TranscriptSegment(index: 0, start: 90, end: 92, text: "Hallo.")
            transcript.segments.append(segment)
            #expect(segment.spokenAt == expected)
        }
    }
}

@MainActor
@Suite("Folders")
struct FolderTests {
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    @Test("Recordings are filed in folders; deleting a folder keeps them")
    func folders() throws {
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())))
        let first = Recording(title: "Eins", source: .microphone)
        let second = Recording(title: "Zwei", source: .meeting)
        container.mainContext.insert(first)
        container.mainContext.insert(second)

        model.createFolder(named: "  Projekt X  ")
        let folder = try #require(try container.mainContext.fetch(FetchDescriptor<Folder>()).first)
        #expect(folder.name == "Projekt X")
        #expect(model.sidebarSelection == .folder(folder.id)) // the new folder is shown

        model.move(recordingIDs: [first.id], to: folder)
        #expect(SidebarItem.folder(folder.id).matches(first))
        #expect(!SidebarItem.folder(folder.id).matches(second))
        #expect(SidebarItem.all.matches(second))

        model.rename(folder, to: "Projekt Y")
        #expect(folder.name == "Projekt Y")

        model.move(recordingIDs: [first.id], to: nil)
        #expect(first.folder == nil)
        model.move(recordingIDs: [first.id, second.id], to: folder)
        model.delete(folder)
        #expect(model.sidebarSelection == .all)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 2)
        #expect(first.folder == nil && second.folder == nil)
    }

    @Test("Revealing a recording outside the selected folder shows all recordings")
    func reveal() throws {
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())))
        let recording = Recording(title: "Lose", source: .microphone)
        container.mainContext.insert(recording)
        model.createFolder(named: "Leer")
        model.reveal(recording)
        #expect(model.sidebarSelection == .all)
        #expect(model.selectedRecordingID == recording.id)
    }
}
