import Foundation
import SwiftData
import Testing
@testable import Scripta

/// A language model that answers from a closure and counts one token per word.
actor FakeLanguageModel: LanguageModelEngine {
    let context: Int
    private let answer: @Sendable (LanguagePrompt) -> String
    private(set) var prompts: [LanguagePrompt] = []

    init(context: Int = 4096, answer: @escaping @Sendable (LanguagePrompt) -> String) {
        self.context = context
        self.answer = answer
    }

    func contextSize() async throws -> Int { context }

    func tokenCount(of text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func generate(_ prompt: LanguagePrompt, maxTokens: Int, onText: @escaping @Sendable (String) -> Void) async throws -> String {
        prompts.append(prompt)
        let text = answer(prompt)
        onText(text)
        return text
    }

    func unload() async {}
}

@Suite("Language models")
struct LanguageModelTests {
    // MARK: - Titles

    @Test("Model answers become clean titles", arguments: [
        ("Titel: Planung des Release 0.5", "Planung des Release 0.5"),
        ("„Budget und Personalplanung“.", "Budget und Personalplanung"),
        ("**Kundentermin mit der Firma Lehmann**", "Kundentermin mit der Firma Lehmann"),
        ("\n\n## Quartalsplanung\nDas Gespräch behandelt …", "Quartalsplanung"),
        ("Title: \"Weekly sync\"", "Weekly sync"),
        ("Eins zwei drei vier fünf sechs sieben acht neun zehn", "Eins zwei drei vier fünf sechs sieben acht"),
    ])
    func cleanTitles(answer: String, expected: String) {
        #expect(TitleSuggestion.cleaned(answer) == expected)
    }

    @Test("An empty or decorative answer gives no title")
    func emptyTitles() {
        #expect(TitleSuggestion.cleaned("") == nil)
        #expect(TitleSuggestion.cleaned("\n---\n„“") == nil)
    }

    @Test("Reasoning blocks are removed, also unfinished ones")
    func reasoning() {
        #expect(ModelOutput.strippingReasoning("<think>hmm</think>\nWochenplanung") == "Wochenplanung")
        #expect(ModelOutput.strippingReasoning("<think>still thinking") == "")
        #expect(ModelOutput.strippingReasoning("planning…</think>Antwort") == "Antwort")
    }

    @Test("German transcripts get German instructions, others English ones")
    func promptLanguage() {
        #expect(PromptLanguage("de") == .german)
        #expect(PromptLanguage("de-AT") == .german)
        #expect(PromptLanguage("fr") == .other("French"))
        #expect(PromptLanguage(nil) == .other("the language of the transcript"))
        let prompt = TitleSuggestion.prompt(for: "Hallo", isComplete: false, languageCode: "de")
        #expect(prompt.request.hasPrefix("Ausschnitte"))
        #expect(prompt.instructions.contains("Titel"))
    }

    @Test("A short transcript goes to the model whole")
    func titleFromWholeTranscript() async throws {
        let model = FakeLanguageModel { _ in "Titel: Release-Planung." }
        let transcript = TranscriptText(paragraphs: ["Wir planen das Release.", "Gut, dann bis Donnerstag."], languageCode: "de")
        let title = try await TitleSuggestion.title(for: transcript, using: model)
        #expect(title == "Release-Planung")
        let request = try #require(await model.prompts.first?.request)
        #expect(request.contains("Wir planen das Release.\nGut, dann bis Donnerstag."))
        #expect(request.hasPrefix("Transkript:"))
    }

    // MARK: - Excerpts and parts

    @Test("A long transcript is sampled from beginning, middle and end")
    func excerpt() async throws {
        let words = (1...3000).map { "w\($0)" }
        let transcript = TranscriptText(paragraphs: [words.joined(separator: " ")], languageCode: "de")
        let excerpt = try await transcript.excerpt(maxTokens: 900) { $0.split(whereSeparator: \.isWhitespace).count }
        let tokens = excerpt.text.split(whereSeparator: \.isWhitespace)
        #expect(!excerpt.isComplete)
        #expect(tokens.count <= 900)
        #expect(tokens.first == "w1")
        #expect(tokens.last == "w3000")
        #expect(tokens.contains("w1500"))
        #expect(excerpt.text.components(separatedBy: "[…]").count == 3)
    }

    @Test("Parts cover the whole transcript and each fits")
    func parts() async throws {
        let paragraphs = (0..<40).map { paragraph in (0..<50).map { "p\(paragraph)w\($0)" }.joined(separator: " ") }
        let transcript = TranscriptText(paragraphs: paragraphs, languageCode: "de")
        let count: (String) async throws -> Int = { $0.split(whereSeparator: \.isWhitespace).count }
        let parts = try await transcript.parts(maxTokens: 300, countTokens: count)
        #expect(parts.count >= 7)
        for part in parts {
            #expect(try await count(part) <= 300)
        }
        let joined = parts.joined(separator: " ").split(whereSeparator: \.isWhitespace)
        #expect(joined.count == 2000)
        #expect(joined.first == "p0w0")
        #expect(joined.last == "p39w49")
    }

    @MainActor
    @Test("Speaker turns become paragraphs; names only for summaries")
    func transcriptText() throws {
        let container = try TestStore.makeContainer()
        let recording = Recording(title: "Weekly", duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        let transcript = try #require(recording.transcript)

        let named = TranscriptText(transcript, namesSpeakers: true)
        #expect(named.paragraphs.count == 7)
        #expect(named.paragraphs[1] == String(localized: "Ich") + ": Ja, laut und deutlich. Guten Morgen!")
        let plain = TranscriptText(transcript, namesSpeakers: false)
        #expect(plain.paragraphs[1] == "Ja, laut und deutlich. Guten Morgen!")
        #expect(plain.languageCode == "de")
    }

    // MARK: - Summaries

    @Test("A transcript that fits is summarized in one step")
    func summaryInOneStep() async throws {
        let model = FakeLanguageModel { _ in "## Kurzfassung\nEs ging um das Release." }
        let transcript = TranscriptText(paragraphs: ["Wir planen das Release."], languageCode: "de")
        let summary = try await SummaryGeneration.summary(of: transcript, using: model) { _ in }
        #expect(summary == "## Kurzfassung\nEs ging um das Release.")
        #expect(await model.prompts.count == 1)
    }

    @Test("A long transcript is summarized part by part, then merged")
    func summaryInParts() async throws {
        let model = FakeLanguageModel(context: 2000) { prompt in
            prompt.request.hasPrefix("Teil") ? "- Notiz" : "## Kurzfassung\nGesamt."
        }
        let paragraphs = (0..<60).map { paragraph in (0..<50).map { "p\(paragraph)w\($0)" }.joined(separator: " ") }
        let transcript = TranscriptText(paragraphs: paragraphs, languageCode: "de")
        let progress = ProgressLog()
        let summary = try await SummaryGeneration.summary(of: transcript, using: model) { progress.append($0) }
        #expect(summary == "## Kurzfassung\nGesamt.")
        let prompts = await model.prompts
        let partCount = prompts.count - 1
        #expect(partCount == 3)
        #expect(prompts.last?.request.hasPrefix("Notizen zu den Teilen") == true)
        #expect(progress.values.first == .part(index: 1, count: partCount))
        #expect(progress.values.contains(.writing("")))
    }

    @Test("Summary blocks: headings, lists, paragraphs")
    func summaryBlocks() {
        let blocks = SummaryBlock.blocks(from: """
        ## Kurzfassung
        Das Team plant **das Release**.

        **Aufgaben:**
        - Anna: Export bis Donnerstag
        *   Ben: Tests
            *   Unit-Tests
        2. Zweiter Punkt
        ---
        """)
        #expect(blocks == [
            .heading("Kurzfassung"),
            .paragraph("Das Team plant **das Release**."),
            .heading("Aufgaben"),
            .listItem(marker: "•", text: "Anna: Export bis Donnerstag", level: 0),
            .listItem(marker: "•", text: "Ben: Tests", level: 0),
            .listItem(marker: "•", text: "Unit-Tests", level: 1),
            .listItem(marker: "2.", text: "Zweiter Punkt", level: 0),
        ])
    }

    @MainActor
    @Test("A summary is stored next to the audio and outdated after edits")
    func summaryStorage() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try TestStore.makeContainer()
        let recording = Recording(title: "Weekly", duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        let transcript = try #require(recording.transcript)

        let summary = TranscriptSummary(text: "## Kurzfassung\nTest", modelName: "Qwen 3.5 4B", createdAt: .now, transcriptModifiedAt: transcript.modifiedAt)
        try summary.save(to: folder)
        let loaded = try #require(TranscriptSummary.load(from: folder))
        #expect(loaded.text == summary.text)
        #expect(!loaded.isOutdated(for: transcript))

        transcript.modifiedAt = transcript.modifiedAt.addingTimeInterval(5)
        #expect(loaded.isOutdated(for: transcript))
    }

    @MainActor
    @Test("The Markdown export puts the summary above the transcript")
    func markdownWithSummary() throws {
        let container = try TestStore.makeContainer()
        let recording = Recording(title: "Weekly", duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        var document = TranscriptDocument(recording: recording, transcript: try #require(recording.transcript))
        document.summary = "## Kurzfassung\nEs ging um das Release."

        let markdown = TranscriptExporter.markdown(document)
        let summaryRange = try #require(markdown.range(of: "## Kurzfassung"))
        let transcriptRange = try #require(markdown.range(of: "## " + String(localized: "Transkript")))
        #expect(summaryRange.lowerBound < transcriptRange.lowerBound)
        #expect(markdown.contains("Guten Morgen zusammen!"))
    }

    // MARK: - Automatic titles

    @Test("Generated titles are recognized in German and English", arguments: [
        ("Aufnahme 26. Okt. 2026, 11:13", true),
        ("Meeting Discord 22. Okt. 2026, 15:26", true),
        ("Recording Oct 26, 2026 at 11:13 AM", true),
        ("Projekt Nordlicht - Krisenmeeting", false),
        ("Meeting mit Anna", false),
        ("PracticeProblem5_1_Muster", false),
    ])
    func generatedTitles(title: String, expected: Bool) {
        #expect(AutomaticTitle.looksGenerated(title) == expected)
    }

    @Test("Downloads skip the model card and git files")
    func neededFiles() {
        #expect(LanguageModelDownloader.isNeeded("model.safetensors"))
        #expect(LanguageModelDownloader.isNeeded("chat_template.jinja"))
        #expect(!LanguageModelDownloader.isNeeded("README.md"))
        #expect(!LanguageModelDownloader.isNeeded(".gitattributes"))
    }
}

/// Collects progress reports from another thread.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [SummaryGeneration.Progress] = []

    func append(_ value: SummaryGeneration.Progress) {
        lock.withLock { log.append(value) }
    }

    var values: [SummaryGeneration.Progress] { lock.withLock { log } }
}

/// Titles applied to recordings through `AppModel`.
@MainActor
@Suite("Automatic titles")
struct AutomaticTitleTests {
    let container: ModelContainer
    let model: AppModel
    let editMenu = UndoManager()
    let defaults: UserDefaults
    let modelsFolder = TestAudio.temporaryDirectory()

    init() throws {
        container = try TestStore.makeContainer()
        defaults = try #require(UserDefaults(suiteName: "AutomaticTitleTests-\(UUID().uuidString)"))
        // A "downloaded" GGUF model, answered by the fake.
        let downloader = LanguageModelDownloader(rootURL: modelsFolder)
        let gguf = try #require(LanguageModelCatalog.all.first { $0.runtime == .gguf })
        try FileManager.default.createDirectory(at: downloader.directory(for: gguf), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: downloader.localURL(for: gguf).path(percentEncoded: false), contents: Data())
        defaults.set(gguf.id, forKey: SettingsKey.titleModel)
        let fake = FakeLanguageModel { _ in "Release-Planung" }
        let service = LanguageModelService(downloader: downloader, defaults: defaults) { _, _ in fake }

        model = AppModel(
            library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())),
            languageModels: service,
            automaticTitle: AutomaticTitle(defaults: defaults)
        )
        editMenu.groupsByEvent = false
        model.attachUndoManager(editMenu)
    }

    private func makeRecording(title: String) throws -> Recording {
        let recording = Recording(title: title, duration: 60, source: .meeting, status: .done, languageCode: "de")
        container.mainContext.insert(recording)
        SampleData.addMeetingTranscript(to: recording)
        try container.mainContext.save()
        return recording
    }

    private func waitForTitleJobs() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        try await Task.sleep(for: .milliseconds(20))
        while !model.languageModels.titleJobs.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    @Test("The first transcript replaces the generated title; ⌘Z brings it back")
    func firstTranscript() async throws {
        let recording = try makeRecording(title: "Meeting 26. Okt. 2026, 11:13")
        model.transcriptStored(recordingID: recording.id, isFirst: true)
        try await waitForTitleJobs()
        #expect(recording.title == "Release-Planung")
        #expect(editMenu.undoActionName == String(localized: "Titel erzeugen"))

        editMenu.undo()
        #expect(recording.title == "Meeting 26. Okt. 2026, 11:13")
    }

    @Test("A title the user gave before transcribing stays")
    func userTitleStays() async throws {
        let recording = try makeRecording(title: "Meeting 26. Okt. 2026, 11:13")
        recording.transcript = nil
        model.rename(recording, to: "Kundentermin Lehmann")
        SampleData.addMeetingTranscript(to: recording)
        model.transcriptStored(recordingID: recording.id, isFirst: true)
        try await waitForTitleJobs()
        #expect(recording.title == "Kundentermin Lehmann")
    }

    @Test("Transcribing again keeps a title that isn't generated")
    func retranscription() async throws {
        let renamed = try makeRecording(title: "Projekt Nordlicht - Krisenmeeting")
        let generated = try makeRecording(title: "Aufnahme 22. Okt. 2026, 23:47")
        model.transcriptStored(recordingID: renamed.id, isFirst: false)
        model.transcriptStored(recordingID: generated.id, isFirst: false)
        try await waitForTitleJobs()
        #expect(renamed.title == "Projekt Nordlicht - Krisenmeeting")
        #expect(generated.title == "Release-Planung")
    }

    @Test("Looking for a summary marks the recording as checked, found or not")
    func summaryLookup() throws {
        let recording = try makeRecording(title: "Weekly")
        #expect(!model.languageModels.checkedSummaryIDs.contains(recording.id))
        #expect(model.summary(for: recording) == nil)
        #expect(model.languageModels.checkedSummaryIDs.contains(recording.id))
    }

    @Test("The setting turns automatic titles off; generating by hand still works")
    func settingOff() async throws {
        defaults.set(false, forKey: SettingsKey.suggestsTitles)
        let recording = try makeRecording(title: "Aufnahme 22. Okt. 2026, 23:47")
        model.transcriptStored(recordingID: recording.id, isFirst: true)
        try await waitForTitleJobs()
        #expect(recording.title == "Aufnahme 22. Okt. 2026, 23:47")

        model.generateTitle(for: recording)
        try await waitForTitleJobs()
        #expect(recording.title == "Release-Planung")
    }
}
