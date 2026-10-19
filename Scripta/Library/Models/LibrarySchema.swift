import Foundation
import SwiftData

/// Version 1 of the persistent library schema.
///
/// The models live in a `VersionedSchema` from day one so that later additions
/// (e.g. AI summaries attached to a `Transcript`) can be shipped as a new schema
/// version with a migration stage instead of a rebuild.
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Recording.self, AudioTrack.self, Transcript.self, TranscriptSegment.self, SpeakerLabel.self]
    }
}

/// Migration plan for the library store. Add new schema versions and stages here.
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// The rest of the app uses the current schema version through these aliases.
typealias Recording = LibrarySchemaV1.Recording
typealias AudioTrack = LibrarySchemaV1.AudioTrack
typealias Transcript = LibrarySchemaV1.Transcript
typealias TranscriptSegment = LibrarySchemaV1.TranscriptSegment
typealias SpeakerLabel = LibrarySchemaV1.SpeakerLabel
