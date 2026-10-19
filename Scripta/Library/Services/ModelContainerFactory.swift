import Foundation
import SwiftData

/// Creates the SwiftData container for the library.
enum ModelContainerFactory {
    /// The on-disk library inside the app container (Application Support).
    static func makePersistent() throws(LibraryError) -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration("Library", schema: schema)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: LibraryMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            throw .storeUnavailable(underlying: error)
        }
    }

    /// A library stored at a custom location (tests use real SQLite behavior).
    static func makeOnDisk(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }

    /// An empty in-memory library for previews, tests and as fallback.
    static func makeInMemory() -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration("InMemoryLibrary", schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // An in-memory store only fails on a broken schema, i.e. a programming error.
            fatalError("In-memory ModelContainer could not be created: \(error)")
        }
    }
}
