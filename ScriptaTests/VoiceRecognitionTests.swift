import Foundation
import SwiftData
import Testing
@testable import Scripta

/// Synthetic 256-d voices: each "person" is a random direction; recordings of
/// that person add a little noise (cosine ≈ 0.9), different people are nearly
/// orthogonal.
private struct SyntheticVoices {
    private var generator = SeededGenerator(seed: 42)

    mutating func person() -> [Float] {
        normalized((0..<256).map { _ in Float.random(in: -1...1, using: &generator) })
    }

    mutating func recording(of person: [Float], noise: Float = 0.3) -> [Float] {
        normalized(person.map { $0 + Float.random(in: -noise...noise, using: &generator) * 0.1 })
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return vector.map { $0 / norm }
    }
}

/// Deterministic random numbers (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Voice matching")
struct VoiceMatcherTests {
    @Test("Unknown people stay unknown; one sample gives a suggestion, not a name")
    func suggestion() {
        var synthetic = SyntheticVoices()
        let max = synthetic.person()
        let voice = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: max), speechSeconds: 60)

        #expect(VoiceMatcher.match([voice], against: []).isEmpty)
        let person = VoiceMatcher.Candidate(id: UUID(), samples: [synthetic.recording(of: max)], confirmedSamples: 1)
        let match = VoiceMatcher.match([voice], against: [person])[voice.id]
        #expect(match?.person == person.id)
        #expect(match?.isAutomatic == false)
    }

    @Test("After three confirmations a clear match is named automatically")
    func automatic() {
        var synthetic = SyntheticVoices()
        let max = synthetic.person()
        let anna = synthetic.person()
        let people = [
            VoiceMatcher.Candidate(id: UUID(), samples: (0..<3).map { _ in synthetic.recording(of: max) }, confirmedSamples: 3),
            VoiceMatcher.Candidate(id: UUID(), samples: [synthetic.recording(of: anna)], confirmedSamples: 1),
        ]
        let long = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: max), speechSeconds: 60)
        let short = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: anna), speechSeconds: 6)
        let matches = VoiceMatcher.match([long, short], against: people)
        #expect(matches[long.id]?.person == people[0].id)
        #expect(matches[long.id]?.isAutomatic == true)
        // Anna has one sample and spoke briefly: only a suggestion.
        #expect(matches[short.id]?.person == people[1].id)
        #expect(matches[short.id]?.isAutomatic == false)
    }

    @Test("Each person is given to one speaker only, the most similar one")
    func exclusive() {
        var synthetic = SyntheticVoices()
        let max = synthetic.person()
        let person = VoiceMatcher.Candidate(id: UUID(), samples: [max], confirmedSamples: 5)
        let close = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: max, noise: 0.1), speechSeconds: 60)
        let farther = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: max, noise: 1.5), speechSeconds: 60)
        let matches = VoiceMatcher.match([farther, close], against: [person])
        #expect(matches[close.id]?.person == person.id)
        #expect(matches[farther.id] == nil)
    }

    @Test("Very short speakers and similar people are never named automatically")
    func caution() {
        var synthetic = SyntheticVoices()
        let max = synthetic.person()
        let twin = synthetic.recording(of: max)
        let people = [
            VoiceMatcher.Candidate(id: UUID(), samples: [max, max, max], confirmedSamples: 3),
            VoiceMatcher.Candidate(id: UUID(), samples: [twin], confirmedSamples: 3),
        ]
        let voice = VoiceMatcher.Voice(id: UUID(), embedding: synthetic.recording(of: max), speechSeconds: 60)
        #expect(VoiceMatcher.match([voice], against: people)[voice.id]?.isAutomatic == false)

        let tiny = VoiceMatcher.Voice(id: UUID(), embedding: max, speechSeconds: 2)
        #expect(VoiceMatcher.match([tiny], against: people).isEmpty)
    }
}

@MainActor
@Suite("Voice library")
struct VoiceLibraryTests {
    private func voice(_ embedding: [Float], seconds: TimeInterval = 60) -> LabelVoice {
        LabelVoice(labelID: UUID(), embedding: embedding, speechSeconds: seconds)
    }

    @Test("While voice recognition is off, nobody is matched or learned")
    func disabled() {
        var synthetic = SyntheticVoices()
        let library = VoiceLibrary.makeInMemory(isEnabled: { false })
        let max = synthetic.person()
        let speaker = voice(max)
        #expect(library.recognize([speaker], recordingID: UUID()).isEmpty)
        library.link(labelID: speaker.labelID, toPersonNamed: "Max")
        #expect(library.statuses[speaker.labelID]?.state == .unknown) // kept for later
        #expect(library.people.isEmpty)
    }

    @Test("Naming teaches a voice: suggestion next time, automatic after three confirmations")
    func learning() {
        var synthetic = SyntheticVoices()
        let library = VoiceLibrary.makeInMemory(isEnabled: { true })
        let max = synthetic.person()

        // Meeting 1: unknown, then named.
        let first = voice(synthetic.recording(of: max))
        #expect(library.recognize([first], recordingID: UUID()).isEmpty)
        #expect(library.statuses[first.labelID]?.state == .unknown)
        library.link(labelID: first.labelID, toPersonNamed: "Max")
        #expect(library.people.map(\.name) == ["Max"])
        #expect(library.people.first?.confirmedSamples == 1)

        // Meetings 2 and 3: guessed (name set, teaches nothing), confirmed by the user.
        for _ in 0..<2 {
            let next = voice(synthetic.recording(of: max))
            #expect(library.recognize([next], recordingID: UUID()) == [next.labelID: "Max"])
            #expect(library.statuses[next.labelID]?.state == .suggested)
            #expect(library.people.first?.samples == library.people.first?.confirmedSamples)
            #expect(library.statuses[next.labelID]?.personName == "Max")
            library.link(labelID: next.labelID, toPersonNamed: "max") // case-insensitive
        }
        #expect(library.people.count == 1)
        #expect(library.people.first?.confirmedSamples == 3)

        // Meeting 4: named automatically.
        let fourth = voice(synthetic.recording(of: max))
        #expect(library.recognize([fourth], recordingID: UUID()) == [fourth.labelID: "Max"])
        #expect(library.statuses[fourth.labelID]?.state == .automatic)
        #expect(library.people.first?.samples == 4)
        #expect(library.namedLabels(of: library.people[0].id).count == 4)
    }

    @Test("Correcting an automatic name moves the voice sample to the right person")
    func correction() {
        var synthetic = SyntheticVoices()
        let library = VoiceLibrary.makeInMemory(isEnabled: { true })
        let max = synthetic.person()
        for _ in 0..<3 {
            let speaker = voice(synthetic.recording(of: max))
            _ = library.recognize([speaker], recordingID: UUID())
            library.link(labelID: speaker.labelID, toPersonNamed: "Max")
        }
        let speaker = voice(synthetic.recording(of: max))
        #expect(library.recognize([speaker], recordingID: UUID())[speaker.labelID] == "Max")
        #expect(library.people.first?.samples == 4)

        // It was actually his brother.
        library.link(labelID: speaker.labelID, toPersonNamed: "Jonas")
        let byName = Dictionary(uniqueKeysWithValues: library.people.map { ($0.name, $0) })
        #expect(byName["Max"]?.samples == 3)
        #expect(byName["Jonas"]?.confirmedSamples == 1)

        // A guest: no sample at all.
        library.unlink(labelID: speaker.labelID)
        #expect(Dictionary(uniqueKeysWithValues: library.people.map { ($0.name, $0.samples) })["Jonas"] == 0)
        #expect(library.statuses[speaker.labelID]?.state == .unknown)
    }

    @Test("The same voice named differently later belongs only to the new person")
    func oneVoiceOnePerson() {
        let library = VoiceLibrary.makeInMemory(isEnabled: { true })
        var synthetic = SyntheticVoices()
        let voiceOfMaximilian = synthetic.person()
        // First transcript: named Max by mistake. Transcribed again: named Maximilian.
        let first = voice(voiceOfMaximilian)
        let again = voice(voiceOfMaximilian)
        _ = library.recognize([first], recordingID: UUID())
        library.link(labelID: first.labelID, toPersonNamed: "Max")
        _ = library.recognize([again], recordingID: UUID())
        library.link(labelID: again.labelID, toPersonNamed: "Maximilian")
        let samples = Dictionary(uniqueKeysWithValues: library.people.map { ($0.name, $0.samples) })
        #expect(samples["Max"] == 0)
        #expect(samples["Maximilian"] == 1)
    }

    @Test("Short speakers give no sample; the same voice twice gives one sample")
    func samples() {
        var synthetic = SyntheticVoices()
        let library = VoiceLibrary.makeInMemory(isEnabled: { true })
        let max = synthetic.person()
        let short = voice(max, seconds: 2)
        _ = library.recognize([short], recordingID: UUID())
        library.link(labelID: short.labelID, toPersonNamed: "Max")
        #expect(library.people.first?.samples == 0)

        // Transcribing the same recording again yields the same fingerprint.
        let again = [voice(max), voice(max)]
        _ = library.recognize(again, recordingID: UUID())
        for speaker in again { library.link(labelID: speaker.labelID, toPersonNamed: "Max") }
        #expect(library.people.first?.samples == 1)
    }

    @Test("Deleting a person or all profiles removes the voice data")
    func deleting() throws {
        var synthetic = SyntheticVoices()
        let library = VoiceLibrary.makeInMemory(isEnabled: { true })
        let speakers = [voice(synthetic.person()), voice(synthetic.person())]
        let recordingID = UUID()
        _ = library.recognize(speakers, recordingID: recordingID)
        library.link(labelID: speakers[0].labelID, toPersonNamed: "Max")
        library.link(labelID: speakers[1].labelID, toPersonNamed: "Anna")

        let max = try #require(library.people.first { $0.name == "Max" })
        library.delete(personID: max.id)
        #expect(library.people.map(\.name) == ["Anna"])
        #expect(library.statuses[speakers[0].labelID]?.state == .unknown)

        library.forgetRecording(recordingID)
        #expect(library.statuses.isEmpty)
        #expect(library.people.map(\.name) == ["Anna"]) // samples belong to the person

        library.deleteAll()
        #expect(library.people.isEmpty)
        #expect((try? library.modelContext.fetchCount(FetchDescriptor<VoiceSample>())) == 0)
    }
}

@MainActor
@Suite("Naming speakers")
struct SpeakerNamingTests {
    let container: ModelContainer

    init() throws {
        container = try TestStore.makeContainer()
    }

    /// A transcript with two diarized speakers whose voices are known to the voice library.
    private func makeTranscript() -> (AppModel, Transcript, SpeakerLabel, SpeakerLabel) {
        let voices = VoiceLibrary.makeInMemory(isEnabled: { true })
        let model = AppModel(
            library: LibraryService(modelContext: container.mainContext, storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory())),
            voices: voices
        )
        let recording = Recording(title: "Meeting", source: .meeting, status: .done)
        container.mainContext.insert(recording)
        let transcript = Transcript(languageCode: "de", engineIdentifier: "test")
        recording.transcript = transcript
        let one = SpeakerLabel(role: .diarized, number: 1)
        let two = SpeakerLabel(role: .diarized, number: 2)
        transcript.speakers.append(contentsOf: [one, two])
        for (index, label) in [one, two].enumerated() {
            let segment = TranscriptSegment(index: index, start: Double(index) * 10, end: Double(index) * 10 + 9, text: "Satz \(index).")
            transcript.segments.append(segment)
            segment.speaker = label
        }
        var synthetic = SyntheticVoices()
        let person = synthetic.person()
        _ = voices.recognize([
            LabelVoice(labelID: one.id, embedding: synthetic.recording(of: person), speechSeconds: 30),
            LabelVoice(labelID: two.id, embedding: synthetic.recording(of: person), speechSeconds: 20),
        ], recordingID: recording.id)
        return (model, transcript, one, two)
    }

    @Test("Naming a speaker creates the person; merging teaches the second voice too")
    func nameAndMerge() {
        let (model, transcript, one, two) = makeTranscript()
        model.rename(one, to: "Max")
        #expect(one.displayName == "Max")
        #expect(model.voices.people.first?.confirmedSamples == 1)

        model.merge(two, into: one)
        #expect(transcript.speakers.map(\.id) == [one.id])
        #expect(model.voices.people.first?.confirmedSamples == 2)
        #expect(model.voices.statuses[two.id] == nil)
    }

    @Test("Moving a passage to another or a new speaker separates two people in one voice")
    func movePassages() throws {
        let (model, transcript, one, two) = makeTranscript()
        model.rename(one, to: "Max")
        #expect(model.voices.people.first?.confirmedSamples == 1)

        // "Max" also contains a passage of someone else.
        let extra = TranscriptSegment(index: 2, start: 30, end: 35, text: "Das war Anna.")
        transcript.segments.append(extra)
        extra.speaker = one
        model.moveToNewSpeaker(extra)
        let anna = try #require(extra.speaker)
        #expect(anna.number == 3 && anna.id != one.id)
        #expect(one.displayName == "Max")
        // The mixed voice no longer teaches Max's profile.
        #expect(model.voices.people.first?.confirmedSamples == 0)
        #expect(model.voices.statuses[one.id] == nil)

        // A known person who isn't a speaker here yet becomes one; the next
        // passage for them joins that speaker.
        let first = TranscriptSegment(index: 3, start: 40, end: 42, text: "Hallo.")
        let second = TranscriptSegment(index: 4, start: 43, end: 45, text: "Tschüss.")
        transcript.segments.append(contentsOf: [first, second])
        first.speaker = one
        second.speaker = one
        model.moveToNewSpeaker(first, named: "Lena")
        model.moveToNewSpeaker(second, named: "lena")
        #expect(first.speaker?.displayName == "Lena")
        #expect(second.speaker?.id == first.speaker?.id)

        // Moving the last passage of a speaker removes it.
        let onlyPassage = try #require(two.segments.first)
        model.move(onlyPassage, to: anna)
        #expect(!transcript.speakers.contains { $0.id == two.id })
        #expect(transcript.speakers.count == 3)
    }

    @Test("Swapping two guessed names in the sheet keeps both speakers")
    func swapNames() {
        let (model, transcript, one, two) = makeTranscript()
        one.customName = "Max"
        two.customName = "Maximilian"
        model.assignNames([
            AppModel.NameAssignment(speaker: one, name: "Maximilian", remember: true),
            AppModel.NameAssignment(speaker: two, name: "Max", remember: true),
        ], in: transcript)
        #expect(transcript.speakers.count == 2)
        #expect(one.displayName == "Maximilian")
        #expect(two.displayName == "Max")

        // The same final name for both still merges them; the renamed speaker stays.
        model.assignNames([AppModel.NameAssignment(speaker: two, name: "maximilian", remember: true)], in: transcript)
        #expect(transcript.speakers.map(\.id) == [two.id])
    }

    @Test("Merging a voice that sounds like someone else teaches nothing")
    func mergeDissimilar() {
        let (model, transcript, one, _) = makeTranscript()
        model.rename(one, to: "Max")
        var synthetic = SyntheticVoices()
        _ = synthetic.person() // the same seed's first voice is Max's
        let stranger = SpeakerLabel(role: .diarized, number: 3)
        transcript.speakers.append(stranger)
        _ = model.voices.recognize([LabelVoice(labelID: stranger.id, embedding: synthetic.person(), speechSeconds: 30)], recordingID: UUID())
        model.merge(stranger, into: one)
        #expect(model.voices.people.first?.confirmedSamples == 1)
    }

    @Test("Guests are named without being remembered")
    func guest() {
        let (model, _, one, _) = makeTranscript()
        model.rename(one, to: "Besuch", remember: false)
        #expect(one.displayName == "Besuch")
        #expect(model.voices.people.isEmpty)
    }

    @Test("Renaming a person renames their speakers in transcripts")
    func renamePerson() throws {
        let (model, transcript, one, _) = makeTranscript()
        model.rename(one, to: "Max")
        let person = try #require(model.voices.people.first)
        model.renamePerson(person.id, to: "Max K.")
        #expect(one.displayName == "Max K.")
        #expect(model.voices.people.first?.name == "Max K.")
        #expect(transcript.speakers.count == 2)
    }
}
