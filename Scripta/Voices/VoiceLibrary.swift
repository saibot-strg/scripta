import Foundation
import SwiftData
import os

/// A known person, for lists and menus.
struct PersonSummary: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var samples: Int
    var confirmedSamples: Int
    var lastHeard: Date?
}

/// What Scripta knows about the voice of a transcript speaker.
struct VoiceStatus: Equatable, Sendable {
    var personID: UUID?
    var personName: String?
    var state: VoiceMatchState
    var score: Double?
    var speechSeconds: Double
}

/// The voice of a speaker in a new transcript.
struct LabelVoice: Sendable {
    var labelID: UUID
    var embedding: [Float]
    var speechSeconds: TimeInterval
}

/// Remembers people's voices and recognizes them in new transcripts.
///
/// Works on its own store (see `VoiceSchemaV1`) and never touches the library:
/// callers apply the names it returns to the `SpeakerLabel`s.
///
/// The anonymous voice of each transcript speaker is always kept (it is
/// derived from the recording and deleted with it), so speakers can still be
/// learned from after the user turns recognition on. People, their samples
/// and any matching exist only once the user turned voice recognition on.
@MainActor
@Observable
final class VoiceLibrary {
    /// Kept alive here: a context whose container is gone crashes on use.
    private let container: ModelContainer
    let modelContext: ModelContext
    @ObservationIgnored private let enabled: () -> Bool

    /// Known people, sorted by name.
    private(set) var people: [PersonSummary] = []
    /// Voice status by `SpeakerLabel.id`.
    private(set) var statuses: [UUID: VoiceStatus] = [:]

    /// Oldest samples beyond this are dropped (unconfirmed ones first).
    static let maximumSamples = 40
    /// A new sample this similar to an existing one replaces it: the same
    /// recording transcribed again. (The same synthetic voice saying other
    /// sentences measured 0.97, real people vary more.)
    static let duplicateSimilarity: Float = 0.995

    init(container: ModelContainer, isEnabled: @escaping () -> Bool = { TranscriptionSettings.recognizesVoices }) {
        self.container = container
        self.modelContext = container.mainContext
        self.enabled = isEnabled
        refresh()
    }

    var isEnabled: Bool { enabled() }

    /// The store in Application Support ("Voices.store"); in memory if it can't be opened.
    static func makePersistent() -> VoiceLibrary {
        let schema = Schema(versionedSchema: VoiceSchemaV1.self)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: VoiceMigrationPlan.self,
                configurations: ModelConfiguration("Voices", schema: schema)
            )
            return VoiceLibrary(container: container)
        } catch {
            Logger.voices.fault("Voice store unavailable: \(error.localizedDescription, privacy: .public)")
            return makeInMemory()
        }
    }

    static func makeInMemory(isEnabled: @escaping () -> Bool = { TranscriptionSettings.recognizesVoices }) -> VoiceLibrary {
        let schema = Schema(versionedSchema: VoiceSchemaV1.self)
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration("InMemoryVoices", schema: schema, isStoredInMemoryOnly: true)
            )
            return VoiceLibrary(container: container, isEnabled: isEnabled)
        } catch {
            fatalError("In-memory voice store could not be created: \(error)")
        }
    }

    // MARK: - Recognition

    /// Stores the voices of a new transcript and matches them with known
    /// people. Returns the names to set: confident matches and guesses alike
    /// (guesses are marked in the UI and teach nothing until confirmed).
    func recognize(_ voices: [LabelVoice], recordingID: UUID) -> [UUID: String] {
        guard !voices.isEmpty else { return [:] }
        let everyone = isEnabled ? allPeople() : []
        let candidates = everyone.map { person in
            VoiceMatcher.Candidate(
                id: person.id,
                samples: person.samples.map(\.vector),
                confirmedSamples: person.samples.count(where: \.isConfirmed)
            )
        }
        let matches = VoiceMatcher.match(
            voices.map { VoiceMatcher.Voice(id: $0.labelID, embedding: $0.embedding, speechSeconds: $0.speechSeconds) },
            against: candidates
        )

        var names: [UUID: String] = [:]
        for voice in voices {
            let row = SpeakerVoice(labelID: voice.labelID, recordingID: recordingID, embedding: voice.embedding, speechSeconds: voice.speechSeconds)
            modelContext.insert(row)
            guard let match = matches[voice.labelID], let person = everyone.first(where: { $0.id == match.person }) else { continue }
            row.personID = person.id
            row.score = Double(match.score)
            if match.isAutomatic {
                row.state = .automatic
                row.sampleID = addSample(to: person, from: row, isConfirmed: false)
            } else {
                row.state = .suggested
            }
            names[voice.labelID] = person.name
            Logger.voices.debug("Speaker matched: score \(match.score, privacy: .private) automatic \(match.isAutomatic, privacy: .public)")
        }
        save()
        return names
    }

    // MARK: - Naming

    /// The user named a speaker: links it to the person with that name
    /// (created if new) and learns the voice.
    func link(labelID: UUID, toPersonNamed name: String) {
        guard isEnabled, let row = voice(ofLabel: labelID) else { return }
        let person = person(named: name) ?? {
            let person = Person(name: name)
            modelContext.insert(person)
            return person
        }()
        if row.personID != person.id {
            removeSample(of: row)
        }
        removeCopies(of: row, outside: person)
        row.personID = person.id
        row.state = .confirmed
        row.sampleID = addSample(to: person, from: row, isConfirmed: true)
        save()
    }

    /// One voice belongs to one person: samples of the same voice in other
    /// profiles (e.g. from a transcript made again and named differently)
    /// are removed, or the two people would be confused from then on.
    private func removeCopies(of voice: SpeakerVoice, outside person: Person) {
        let vector = voice.vector
        for other in allPeople() where other.id != person.id {
            for sample in other.samples where sample.labelID == voice.labelID
                || VoiceMatcher.cosine(sample.vector, vector) >= Self.duplicateSimilarity {
                other.samples.removeAll { $0.id == sample.id }
                modelContext.delete(sample)
            }
        }
    }

    /// The speaker is nobody to remember (a guest) or was renamed back: drops
    /// the link and the sample it gave.
    func unlink(labelID: UUID) {
        guard let row = voice(ofLabel: labelID), row.personID != nil else { return }
        removeSample(of: row)
        row.personID = nil
        row.score = nil
        row.state = .unknown
        save()
    }

    /// Puts a speaker's voice back to an earlier status (undoing a naming):
    /// the sample it gave goes back to the person it belonged to, or away,
    /// so an undone naming leaves no voice in the wrong profile. A person
    /// left without samples and speakers by this (created by the naming) is
    /// removed.
    func restore(labelID: UUID, to status: VoiceStatus?) {
        guard let row = voice(ofLabel: labelID) else { return }
        let previousPersonID = row.personID
        removeSample(of: row)
        let person = status?.personID.flatMap(person(withID:))
        row.personID = person?.id
        row.score = person == nil ? nil : status?.score
        row.state = person == nil ? .unknown : status?.state ?? .unknown
        if let person, row.state == .confirmed || row.state == .automatic {
            row.sampleID = addSample(to: person, from: row, isConfirmed: row.state == .confirmed)
        }
        if let previousPersonID, previousPersonID != row.personID, let previous = self.person(withID: previousPersonID),
           previous.samples.isEmpty, !allVoices().contains(where: { $0.personID == previousPersonID }) {
            modelContext.delete(previous)
        }
        save()
    }

    /// Two speakers of a transcript are one person: the merged speaker's voice
    /// becomes another sample of the target's person, but only if it sounds
    /// like that person. Merging is also how users clean up a mix-up, and a
    /// dissimilar voice would spoil the profile.
    func merge(labelID: UUID, into targetID: UUID) {
        guard let source = voice(ofLabel: labelID) else { return }
        if isEnabled, let target = voice(ofLabel: targetID), target.state == .confirmed || target.state == .automatic,
           let personID = target.personID, let person = person(withID: personID),
           VoiceMatcher.score(source.vector, samples: person.samples.map(\.vector)) >= VoiceMatcher.suggestionThreshold {
            if source.personID != personID { removeSample(of: source) }
            _ = addSample(to: person, from: source, isConfirmed: true)
        } else {
            removeSample(of: source)
        }
        modelContext.delete(source)
        save()
    }

    /// The speaker turned out to mix several people (the user moved passages
    /// out of it): its voice is no fingerprint of one person, so it is dropped,
    /// together with any sample it gave.
    func discardVoice(labelID: UUID) {
        guard let row = voice(ofLabel: labelID) else { return }
        removeSample(of: row)
        modelContext.delete(row)
        save()
    }

    /// The speakers no longer exist (transcript replaced or deleted). Their
    /// samples stay: they belong to the people now.
    func forget(labelIDs: [UUID]) {
        guard !labelIDs.isEmpty else { return }
        for row in allVoices() where labelIDs.contains(row.labelID) {
            modelContext.delete(row)
        }
        save()
    }

    func forgetRecording(_ recordingID: UUID) {
        for row in allVoices() where row.recordingID == recordingID {
            modelContext.delete(row)
        }
        save()
    }

    // MARK: - People

    /// Renames a person. Returns the speakers that carry the name, so the
    /// caller can update them.
    @discardableResult
    func rename(personID: UUID, to name: String) -> [UUID] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let person = person(withID: personID) else { return [] }
        person.name = trimmed
        save()
        return namedLabels(of: personID)
    }

    /// Speakers named after the person (automatically or by the user).
    func namedLabels(of personID: UUID) -> [UUID] {
        allVoices()
            .filter { $0.personID == personID && ($0.state == .automatic || $0.state == .confirmed) }
            .map(\.labelID)
    }

    /// Deletes a person and their samples. Transcripts keep the names.
    func delete(personID: UUID) {
        for row in allVoices() where row.personID == personID {
            row.personID = nil
            row.score = nil
            row.sampleID = nil
            row.state = .unknown
        }
        if let person = person(withID: personID) {
            modelContext.delete(person)
        }
        save()
    }

    /// Deletes every voice profile and fingerprint. Transcripts keep the names.
    func deleteAll() {
        // One by one: SwiftData's batch delete fails on the person–sample relationship.
        for person in allPeople() { modelContext.delete(person) }
        for sample in (try? modelContext.fetch(FetchDescriptor<VoiceSample>())) ?? [] { modelContext.delete(sample) }
        for row in allVoices() { modelContext.delete(row) }
        save()
    }

    // MARK: - Samples

    /// Adds a sample of the speaker's voice to the person (or refreshes the
    /// one it already gave). Short speakers give no sample.
    private func addSample(to person: Person, from voice: SpeakerVoice, isConfirmed: Bool) -> UUID? {
        guard voice.speechSeconds >= VoiceMatcher.minimumSpeechForSample else { return nil }
        let vector = voice.vector
        if let existing = person.samples.first(where: {
            $0.labelID == voice.labelID || VoiceMatcher.cosine($0.vector, vector) >= Self.duplicateSimilarity
        }) {
            existing.embedding = voice.embedding
            existing.speechSeconds = voice.speechSeconds
            existing.isConfirmed = existing.isConfirmed || isConfirmed
            existing.labelID = voice.labelID
            return existing.id
        }
        let sample = VoiceSample(
            embedding: vector, speechSeconds: voice.speechSeconds, isConfirmed: isConfirmed,
            recordingID: voice.recordingID, labelID: voice.labelID
        )
        modelContext.insert(sample)
        person.samples.append(sample)
        trimSamples(of: person)
        return sample.id
    }

    private func trimSamples(of person: Person) {
        let excess = person.samples.count - Self.maximumSamples
        guard excess > 0 else { return }
        let oldestFirst = person.samples.sorted { ($0.isConfirmed ? 1 : 0, $0.createdAt) < ($1.isConfirmed ? 1 : 0, $1.createdAt) }
        for sample in oldestFirst.prefix(excess) {
            person.samples.removeAll { $0.id == sample.id }
            modelContext.delete(sample)
        }
    }

    private func removeSample(of voice: SpeakerVoice) {
        guard let sampleID = voice.sampleID else { return }
        let descriptor = FetchDescriptor<VoiceSample>(predicate: #Predicate { $0.id == sampleID })
        for sample in (try? modelContext.fetch(descriptor)) ?? [] {
            sample.person?.samples.removeAll { $0.id == sample.id }
            modelContext.delete(sample)
        }
        voice.sampleID = nil
    }

    // MARK: - Store

    private func voice(ofLabel labelID: UUID) -> SpeakerVoice? {
        let descriptor = FetchDescriptor<SpeakerVoice>(predicate: #Predicate { $0.labelID == labelID })
        return try? modelContext.fetch(descriptor).first
    }

    private func person(withID id: UUID) -> Person? {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func person(named name: String) -> Person? {
        allPeople().first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func allPeople() -> [Person] {
        (try? modelContext.fetch(FetchDescriptor<Person>())) ?? []
    }

    private func allVoices() -> [SpeakerVoice] {
        (try? modelContext.fetch(FetchDescriptor<SpeakerVoice>())) ?? []
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            Logger.voices.error("Could not save voices: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// Rebuilds the observable snapshots (also after undo and redo).
    func refresh() {
        let everyone = allPeople()
        people = everyone
            .map { person in
                PersonSummary(
                    id: person.id,
                    name: person.name,
                    samples: person.samples.count,
                    confirmedSamples: person.samples.count(where: \.isConfirmed),
                    lastHeard: person.samples.map(\.createdAt).max()
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let names = Dictionary(uniqueKeysWithValues: everyone.map { ($0.id, $0.name) })
        statuses = Dictionary(allVoices().map { row in
            (row.labelID, VoiceStatus(
                personID: row.personID,
                personName: row.personID.flatMap { names[$0] },
                state: row.state,
                score: row.score,
                speechSeconds: row.speechSeconds
            ))
        }, uniquingKeysWith: { first, _ in first })
    }
}
