import Accelerate
import Foundation

/// Decides which known person a transcript speaker is, from voice embeddings.
///
/// A speaker is compared with each person's samples (cosine similarity, mean
/// of the best three: people sound different over Teams, in a room or on a
/// headset, and each sample covers one of those). Every person gets at most
/// one speaker per transcript. A name is only given automatically when the
/// match is strong, clearly better than the next person, and the person has
/// been confirmed by the user a few times; otherwise it stays a suggestion.
enum VoiceMatcher {
    /// Below this, a speaker stays unknown.
    static let suggestionThreshold: Float = 0.5
    /// From this on (and with the conditions below), the name is set automatically.
    static let automaticThreshold: Float = 0.7
    /// How much better than the second-best person an automatic match must be.
    static let automaticMargin: Float = 0.1
    /// Confirmed samples a person needs before names are set automatically.
    static let confirmedSamplesForAutomatic = 3
    /// Shorter speakers are too uncertain to match at all.
    static let minimumSpeechForMatch: TimeInterval = 3
    static let minimumSpeechForAutomatic: TimeInterval = 10
    /// Shorter speakers don't become samples (their embedding is noisy).
    static let minimumSpeechForSample: TimeInterval = 5
    /// Samples compared per person.
    static let bestSamples = 3

    struct Voice: Sendable {
        var id: UUID
        var embedding: [Float]
        var speechSeconds: TimeInterval
    }

    struct Candidate: Sendable {
        var id: UUID
        var samples: [[Float]]
        var confirmedSamples: Int
    }

    struct Match: Equatable, Sendable {
        var person: UUID
        var score: Float
        var isAutomatic: Bool
    }

    /// The best person per voice (by `Voice.id`); voices without a match are missing.
    static func match(_ voices: [Voice], against people: [Candidate]) -> [UUID: Match] {
        let eligible = voices.filter { $0.speechSeconds >= minimumSpeechForMatch && !$0.embedding.isEmpty }
        var scores: [UUID: [UUID: Float]] = [:]
        for voice in eligible {
            for person in people where !person.samples.isEmpty {
                scores[voice.id, default: [:]][person.id] = score(voice.embedding, samples: person.samples)
            }
        }

        // Strongest pairs first; each voice and each person is used once.
        let pairs = scores.flatMap { voice, byPerson in
            byPerson.filter { $0.value >= suggestionThreshold }.map { (voice: voice, person: $0.key, score: $0.value) }
        }
        .sorted { $0.score > $1.score }

        var matches: [UUID: Match] = [:]
        var takenPeople: Set<UUID> = []
        for pair in pairs where matches[pair.voice] == nil && !takenPeople.contains(pair.person) {
            guard let voice = eligible.first(where: { $0.id == pair.voice }),
                  let person = people.first(where: { $0.id == pair.person }) else { continue }
            let runnerUp = scores[pair.voice]?.filter { $0.key != pair.person }.values.max() ?? -1
            let isAutomatic = pair.score >= automaticThreshold
                && pair.score - runnerUp >= automaticMargin
                && person.confirmedSamples >= confirmedSamplesForAutomatic
                && voice.speechSeconds >= minimumSpeechForAutomatic
            matches[pair.voice] = Match(person: pair.person, score: pair.score, isAutomatic: isAutomatic)
            takenPeople.insert(pair.person)
        }
        return matches
    }

    /// Mean similarity to the person's closest samples.
    static func score(_ embedding: [Float], samples: [[Float]]) -> Float {
        let similarities = samples.map { cosine(embedding, $0) }.sorted(by: >).prefix(bestSamples)
        guard !similarities.isEmpty else { return -1 }
        return similarities.reduce(0, +) / Float(similarities.count)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        let dot = vDSP.dot(a, b)
        let norms = (vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b)).squareRoot()
        return norms > 0 ? dot / norms : -1
    }
}
