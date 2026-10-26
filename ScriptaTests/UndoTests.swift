import Foundation
import SwiftData
import Testing
@testable import Scripta

/// ⌘Z for the user's own edits (`UndoCoordinator` through `AppModel`).
@MainActor
@Suite("Undo")
struct UndoTests {
    let container: ModelContainer
    let model: AppModel
    /// Stands in for the main window's undo manager (the Edit menu).
    let editMenu = UndoManager()

    init() throws {
        container = try TestStore.makeContainer()
        model = AppModel(library: LibraryService(
            modelContext: container.mainContext,
            storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())
        ))
        editMenu.groupsByEvent = false
        model.attachUndoManager(editMenu)
    }

    private func makeMeeting() throws -> (Recording, Transcript) {
        let recording = Recording(title: "Weekly", duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        try container.mainContext.save()
        return (recording, try #require(recording.transcript))
    }

    @Test("A text correction can be undone and redone")
    func undoEdit() throws {
        let (_, transcript) = try makeMeeting()
        let segment = try #require(transcript.orderedSegments.first)
        let original = segment.text

        model.edit(segment, text: "Guten Morgen!")
        #expect(segment.text == "Guten Morgen!")
        #expect(editMenu.canUndo)
        #expect(editMenu.undoActionName == String(localized: "Text bearbeiten"))

        editMenu.undo()
        #expect(segment.text == original)
        #expect(!segment.isEdited)
        #expect(transcript.fullText.contains(original))

        editMenu.redo()
        #expect(segment.text == "Guten Morgen!")
        #expect(segment.isEdited)

        editMenu.undo()
        #expect(segment.text == original)
    }

    @Test("Merging two speakers can be undone")
    func undoMerge() throws {
        let (_, transcript) = try makeMeeting()
        let speakers = transcript.speakers.filter { $0.role == .diarized }.sorted { $0.number < $1.number }
        let (lead, colleague) = (speakers[0], speakers[1])
        let colleaguePassages = Set(colleague.segments.map(\.id))

        model.merge(colleague, into: lead)
        #expect(transcript.speakers.count == 2)

        editMenu.undo()
        #expect(transcript.speakers.count == 3)
        let restored = try #require(transcript.speakers.first { $0.role == .diarized && $0.number == 2 })
        #expect(Set(restored.segments.map(\.id)) == colleaguePassages)
    }

    @Test("Background changes are not undone with the user's step")
    func backgroundChangesStayOut() throws {
        let (recording, transcript) = try makeMeeting()
        let segment = try #require(transcript.orderedSegments.first)

        model.edit(segment, text: "Korrigiert")
        // Like the transcription service: a status change outside any user action.
        recording.status = .queued
        try container.mainContext.save()

        editMenu.undo()
        #expect(segment.text != "Korrigiert")
        #expect(recording.status == .queued)
        #expect(!editMenu.canUndo)
    }

    @Test("Each user action is its own step")
    func separateSteps() throws {
        let (recording, transcript) = try makeMeeting()
        let segment = try #require(transcript.orderedSegments.first)

        model.rename(recording, to: "Team-Weekly")
        model.edit(segment, text: "Korrigiert")

        editMenu.undo()
        #expect(recording.title == "Team-Weekly")
        #expect(segment.text != "Korrigiert")
        editMenu.undo()
        #expect(recording.title == "Weekly")
    }

    @Test("Undoing a new folder removes it and leaves the folder selection")
    func undoNewFolder() throws {
        model.createFolder(named: "Kunden")
        let folder = try #require(try container.mainContext.fetch(FetchDescriptor<Folder>()).first)
        #expect(model.sidebarSelection == .folder(folder.id))

        editMenu.undo()
        #expect(try container.mainContext.fetch(FetchDescriptor<Folder>()).isEmpty)
        #expect(model.sidebarSelection == .all)
    }

    @Test("Deleting a recording drops older steps, which could point into it")
    func deleteClearsSteps() throws {
        let (recording, transcript) = try makeMeeting()
        let segment = try #require(transcript.orderedSegments.first)
        model.edit(segment, text: "Korrigiert")
        #expect(editMenu.canUndo)

        model.delete(recording)
        #expect(!editMenu.canUndo)
    }

    @Test("Deleting a folder can be undone, with its recordings back in it")
    func undoDeleteFolder() throws {
        let (recording, _) = try makeMeeting()
        model.createFolder(named: "Kunden")
        let folder = try #require(try container.mainContext.fetch(FetchDescriptor<Folder>()).first)
        model.move(recordingIDs: [recording.id], to: folder)
        let folderID = folder.id

        model.delete(folder)
        #expect(recording.folder == nil)
        editMenu.undo()
        #expect(recording.folder?.id == folderID)
        #expect(recording.folder?.name == "Kunden")
        editMenu.redo()
        #expect(recording.folder == nil)
    }

    @Test("Moving a passage to a new speaker can be undone")
    func undoMoveToNewSpeaker() throws {
        let (_, transcript) = try makeMeeting()
        let segment = try #require(transcript.orderedSegments.first)
        let original = try #require(segment.speaker?.id)

        model.moveToNewSpeaker(segment)
        #expect(transcript.speakers.count == 4)
        #expect(segment.speaker?.number == 3)

        editMenu.undo()
        #expect(transcript.speakers.count == 3)
        #expect(segment.speaker?.id == original)
    }

    @Test("Undoing a name takes the voice sample back out of the person's profile")
    func undoNameKeepsProfilesClean() throws {
        let voices = VoiceLibrary.makeInMemory(isEnabled: { true })
        let model = AppModel(library: LibraryService(
            modelContext: container.mainContext,
            storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())
        ), voices: voices)
        model.attachUndoManager(editMenu)
        let (recording, transcript) = try makeMeeting()
        let speaker = try #require(transcript.speakers.first { $0.number == 1 })
        let norm = Float(256).squareRoot()
        _ = voices.recognize([LabelVoice(labelID: speaker.id, embedding: (0..<256).map { _ in 1 / norm }, speechSeconds: 30)], recordingID: recording.id)

        model.rename(speaker, to: "Max")
        #expect(voices.people.first?.confirmedSamples == 1)

        editMenu.undo()
        #expect(speaker.customName == nil)
        #expect(voices.statuses[speaker.id]?.personID == nil)
        // "Max" only existed because of the undone naming.
        #expect(voices.people.isEmpty)

        editMenu.redo()
        #expect(speaker.customName == "Max")
    }

    @Test("Without a window, actions still work but aren't undoable")
    func noWindow() throws {
        model.attachUndoManager(nil)
        let (recording, _) = try makeMeeting()
        model.rename(recording, to: "Neu")
        #expect(recording.title == "Neu")
        #expect(!editMenu.canUndo)
    }
}
