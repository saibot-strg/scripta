import Foundation
import SwiftData

/// Version 3 of the persistent library schema: recordings remember the name
/// of their folder on disk, which is named after the title.
///
/// The models live in a `VersionedSchema` so that additions ship as a new
/// schema version with a migration stage instead of a rebuild. Previous
/// versions are kept, frozen, in `LibrarySchemaV1.swift` and `LibrarySchemaV2.swift`.
enum LibrarySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Recording.self, AudioTrack.self, Transcript.self, TranscriptSegment.self, SpeakerLabel.self, Folder.self]
    }
}

/// Migration plan for the library store. Add new schema versions and stages here.
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self] }

    static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

    /// Folders are new and optional: nothing to convert.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)

    /// The folder name is new and optional: existing recordings keep their
    /// ID-named folders until `LibraryService.nameFiles(of:)` renames them.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self)
}

// The rest of the app uses the current schema version through these aliases.
typealias Recording = LibrarySchemaV3.Recording
typealias AudioTrack = LibrarySchemaV3.AudioTrack
typealias Transcript = LibrarySchemaV3.Transcript
typealias TranscriptSegment = LibrarySchemaV3.TranscriptSegment
typealias SpeakerLabel = LibrarySchemaV3.SpeakerLabel
typealias Folder = LibrarySchemaV3.Folder
