import SwiftUI

extension SpeakerLabel {
    private static let palette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown]

    /// Accent for "Ich", neutral for everyone else, distinct hues for diarized
    /// speakers (repeating after six).
    var tint: Color {
        switch role {
        case .me: .accentColor
        case .others: .secondary
        case .diarized: Self.palette[(max(number, 1) - 1) % Self.palette.count]
        }
    }

    /// The name was set from a guess and not confirmed yet.
    @MainActor
    func isGuess(in voices: VoiceLibrary) -> Bool {
        guard let status = voices.statuses[id], status.state == .suggested, let name = status.personName else { return false }
        return customName == name
    }

    /// Menu order: "Ich" first, then "Andere" and the numbered speakers.
    static func menuOrder(_ lhs: SpeakerLabel, _ rhs: SpeakerLabel) -> Bool {
        (lhs.role == .me ? 0 : 1, lhs.number) < (rhs.role == .me ? 0 : 1, rhs.number)
    }
}
