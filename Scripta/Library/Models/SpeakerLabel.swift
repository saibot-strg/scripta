import Foundation
import SwiftData

extension LibrarySchemaV1 {
    /// A speaker within one transcript ("Ich", "Andere" or a diarized speaker).
    @Model
    final class SpeakerLabel {
        var id: UUID
        var roleRaw: String
        /// 1-based number for diarized speakers, 0 otherwise.
        var number: Int
        /// Name set by the user; overrides the generated display name.
        var customName: String?
        var transcript: Transcript?

        @Relationship(deleteRule: .nullify, inverse: \TranscriptSegment.speaker)
        var segments: [TranscriptSegment] = []

        init(role: SpeakerRole, number: Int = 0, customName: String? = nil) {
            self.id = UUID()
            self.roleRaw = role.rawValue
            self.number = number
            self.customName = customName
        }
    }
}

extension SpeakerLabel {
    var role: SpeakerRole {
        get { SpeakerRole(rawValue: roleRaw) ?? .others }
        set { roleRaw = newValue.rawValue }
    }

    var isLocalUser: Bool { role == .me }

    /// Localized at display time so the UI language can change later.
    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        switch role {
        case .me: return String(localized: "Ich")
        case .others: return String(localized: "Andere")
        case .diarized: return String(localized: "Sprecher \(number)")
        }
    }
}
