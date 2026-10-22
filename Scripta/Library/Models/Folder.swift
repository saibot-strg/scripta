import Foundation
import SwiftData

extension LibrarySchemaV2 {
    /// A folder in the sidebar. A recording is in at most one folder;
    /// deleting a folder keeps its recordings.
    @Model
    final class Folder {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date

        @Relationship(deleteRule: .nullify, inverse: \Recording.folder)
        var recordings: [Recording] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = .now
        }
    }
}
