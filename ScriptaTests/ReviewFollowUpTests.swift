import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Meeting notice")
struct MeetingNoticeTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "ScriptaTests-\(UUID().uuidString)"))
    }

    @Test("Asked before the first meeting; cancelling doesn't start and asks again")
    func cancelAsksAgain() async {
        var asked = 0
        let notice = MeetingNotice(defaults: defaults, present: { asked += 1; return false })
        #expect(await !notice.confirm())
        #expect(await !notice.confirm())
        #expect(asked == 2)
    }

    @Test("Once confirmed, later meetings start without asking")
    func confirmedOnce() async {
        var asked = 0
        let notice = MeetingNotice(defaults: defaults, present: { asked += 1; return true })
        #expect(await notice.confirm())
        #expect(await notice.confirm())
        #expect(asked == 1)
    }
}

@Suite("App language")
struct AppLanguageTests {
    @Test("The choice is stored as the app's AppleLanguages and read back")
    func storeAndRead() throws {
        let suite = "ScriptaTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppLanguage.stored(in: defaults, bundleID: suite) == .system)
        AppLanguage.english.store(in: defaults)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
        #expect(AppLanguage.stored(in: defaults, bundleID: suite) == .english)
        AppLanguage.system.store(in: defaults)
        #expect(AppLanguage.stored(in: defaults, bundleID: suite) == .system)
    }
}

@Suite("Deleting to the Trash")
struct TrashTests {
    @Test("The trashed folder is named after the recording")
    func readableName() {
        let id = UUID(uuidString: "3F2A9C1B-0000-0000-0000-000000000000")!
        #expect(RecordingStorage.trashName(title: "Weekly 26.10.", id: id) == "Weekly 26.10. (3F2A9C1B)")
        #expect(RecordingStorage.trashName(title: "Kunde/Projekt: Start", id: id) == "Kunde-Projekt- Start (3F2A9C1B)")
        #expect(RecordingStorage.trashName(title: "  ", id: id) == "3F2A9C1B")
    }

    @Test("Temporary folders (tests, previews) are deleted, not trashed")
    func temporaryIsDeleted() throws {
        let storage = RecordingStorage(rootURL: TestAudio.temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: storage.rootURL) }
        let id = UUID()
        try storage.makeFolder(for: id)
        try storage.trashFolder(for: id, title: "Test")
        #expect(!FileManager.default.fileExists(atPath: storage.folderURL(for: id).path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.rootURL.path(percentEncoded: false)).isEmpty)
    }
}

@MainActor
@Suite("Live recordings in the list")
struct LiveRecordingTests {
    @Test("Shown under all recordings and their own source only")
    func filters() {
        let meeting = LiveRecording(id: UUID(), title: "Meeting", source: .meeting)
        #expect(SidebarItem.all.matches(meeting))
        #expect(SidebarItem.filter(.meetings).matches(meeting))
        #expect(!SidebarItem.filter(.microphone).matches(meeting))
        #expect(!SidebarItem.filter(.notTranscribed).matches(meeting))
        #expect(!SidebarItem.folder(UUID()).matches(meeting))
    }

    @Test("The running recording is listed, then saved under the same ID")
    func sameIDWhenSaved() async throws {
        let root = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try TestStore.makeContainer()
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: root)))
        model.recorder.usesTestTone = true

        await model.startRecording()
        let live = try #require(model.liveRecordings.first)
        #expect(model.liveRecordings.count == 1)
        #expect(live.source == .microphone)
        #expect(!live.isSaving)
        try await Task.sleep(for: .milliseconds(500))

        let saving = model.stopRecording()
        #expect(model.liveRecordings.first?.isSaving == true)
        await saving?.value

        #expect(model.liveRecordings.isEmpty)
        #expect(model.library.recording(withID: live.id) != nil)
        #expect(model.selectedRecordingID == live.id)
        try await model.waitForEncoding()
    }
}

@MainActor
@Suite("Transcript layout and re-transcription")
struct TranscriptLayoutTests {
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    private func makeMeeting() throws -> Recording {
        let recording = Recording(title: "Weekly", duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        try container.mainContext.save()
        return recording
    }

    @Test("Rows follow playback order and mark speaker turns")
    func rows() throws {
        let transcript = try #require(try makeMeeting().transcript)
        let layout = TranscriptLayout(transcript)
        #expect(layout.rows.map(\.id) == transcript.orderedSegments.map(\.id))
        #expect(layout.rows.first?.isFirst == true)
        #expect(layout.rows.allSatisfy { $0.isNewSpeaker })  // the sample alternates speakers
        #expect(layout.isCurrent(for: transcript))
        #expect(layout.timeline.segmentID(at: 0) == nil)
        #expect(layout.timeline.segmentID(at: 2) == layout.rows.first?.id)
    }

    @Test("An edit makes the cached layout outdated")
    func outdatedAfterEdit() throws {
        let transcript = try #require(try makeMeeting().transcript)
        let layout = TranscriptLayout(transcript)
        transcript.rebuildFullText()
        #expect(!layout.isCurrent(for: transcript))
    }

    @Test("Transcribing again asks first only when there are corrections or names")
    func asksBeforeDiscarding() throws {
        let model = AppModel(library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())))
        let recording = try makeMeeting()
        let transcript = try #require(recording.transcript)
        #expect(!transcript.hasManualChanges)

        try #require(transcript.orderedSegments.first).applyEdit("Korrigiert")
        #expect(transcript.hasManualChanges)
        model.requestTranscription(of: recording)
        #expect(model.retranscriptionRequest?.id == recording.id)
        #expect(recording.status == .done)
    }
}
