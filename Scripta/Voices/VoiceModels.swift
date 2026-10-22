import Foundation
import SwiftData

/// Version 1 of the voice store. Voice fingerprints are biometric data, so
/// they live in a store of their own, apart from the library: deleting all
/// voice profiles is deleting this store's content, nothing else.
enum VoiceSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Person.self, VoiceSample.self, SpeakerVoice.self]
    }
}

enum VoiceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VoiceSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias Person = VoiceSchemaV1.Person
typealias VoiceSample = VoiceSchemaV1.VoiceSample
typealias SpeakerVoice = VoiceSchemaV1.SpeakerVoice

extension VoiceSchemaV1 {
    /// Someone Scripta recognizes by their voice.
    @Model
    final class Person {
        var id: UUID
        var name: String
        var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \VoiceSample.person)
        var samples: [VoiceSample] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = .now
        }
    }

    /// One voice fingerprint of a person, taken from one recording.
    @Model
    final class VoiceSample {
        var id: UUID
        /// 256 Float32 values (WeSpeaker embedding).
        var embedding: Data
        var speechSeconds: Double
        /// Named or confirmed by the user, not only recognized automatically.
        var isConfirmed: Bool
        var recordingID: UUID?
        /// The transcript speaker it came from.
        var labelID: UUID?
        var createdAt: Date
        var person: Person?

        init(embedding: [Float], speechSeconds: Double, isConfirmed: Bool, recordingID: UUID?, labelID: UUID?) {
            self.id = UUID()
            self.embedding = VoiceEmbedding.data(embedding)
            self.speechSeconds = speechSeconds
            self.isConfirmed = isConfirmed
            self.recordingID = recordingID
            self.labelID = labelID
            self.createdAt = .now
        }
    }

    /// The voice of one speaker in a transcript. Speakers (`SpeakerLabel`)
    /// live in the library; this links them by ID.
    @Model
    final class SpeakerVoice {
        @Attribute(.unique) var labelID: UUID
        var recordingID: UUID
        var embedding: Data
        var speechSeconds: Double
        var personID: UUID?
        var stateRaw: String
        var score: Double?
        /// The sample this voice gave `personID`; moved when the user corrects the name.
        var sampleID: UUID?

        init(labelID: UUID, recordingID: UUID, embedding: [Float], speechSeconds: Double) {
            self.labelID = labelID
            self.recordingID = recordingID
            self.embedding = VoiceEmbedding.data(embedding)
            self.speechSeconds = speechSeconds
            self.stateRaw = VoiceMatchState.unknown.rawValue
        }
    }
}

/// How a transcript speaker relates to a known person.
enum VoiceMatchState: String, Codable, Sendable {
    /// Not recognized.
    case unknown
    /// Probably this person: the name is set but marked as a guess ("?")
    /// until the user confirms it. Guesses teach nothing.
    case suggested
    /// Recognized with confidence and named automatically.
    case automatic
    /// Named or confirmed by the user.
    case confirmed
}

extension SpeakerVoice {
    var state: VoiceMatchState {
        get { VoiceMatchState(rawValue: stateRaw) ?? .unknown }
        set { stateRaw = newValue.rawValue }
    }

    var vector: [Float] { VoiceEmbedding.vector(embedding) }
}

extension VoiceSample {
    var vector: [Float] { VoiceEmbedding.vector(embedding) }
}

/// Stores embeddings compactly as raw Float32 bytes.
enum VoiceEmbedding {
    static func data(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
