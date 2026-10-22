import Foundation
import SwiftData

extension LibrarySchemaV2 {
    /// One audio file belonging to a recording (e.g. the meeting mix, or the
    /// separate microphone and system tracks used for "Ich" / "Andere").
    @Model
    final class AudioTrack {
        var id: UUID
        var roleRaw: String
        /// File name inside the recording's folder.
        var fileName: String
        var duration: TimeInterval
        var recording: Recording?

        init(id: UUID = UUID(), role: TrackRole, fileName: String, duration: TimeInterval = 0) {
            self.id = id
            self.roleRaw = role.rawValue
            self.fileName = fileName
            self.duration = duration
        }
    }
}

extension AudioTrack {
    var role: TrackRole {
        get { TrackRole(rawValue: roleRaw) ?? .primary }
        set { roleRaw = newValue.rawValue }
    }
}
