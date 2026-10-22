import Foundation
import SwiftData

/// Version 2 of the persistent library schema: adds folders.
///
/// The models live in a `VersionedSchema` so that additions ship as a new
/// schema version with a migration stage instead of a rebuild. The previous
/// version is kept, frozen, in `LibrarySchemaV1.swift`.
enum LibrarySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Recording.self, AudioTrack.self, Transcript.self, TranscriptSegment.self, SpeakerLabel.self, Folder.self]
    }
}

/// Migration plan for the library store. Add new schema versions and stages here.
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self] }

    static var stages: [MigrationStage] { [v1ToV2] }

    /// Folders are new and optional: nothing to convert.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)
}

// The rest of the app uses the current schema version through these aliases.
typealias Recording = LibrarySchemaV2.Recording
typealias AudioTrack = LibrarySchemaV2.AudioTrack
typealias Transcript = LibrarySchemaV2.Transcript
typealias TranscriptSegment = LibrarySchemaV2.TranscriptSegment
typealias SpeakerLabel = LibrarySchemaV2.SpeakerLabel
typealias Folder = LibrarySchemaV2.Folder
