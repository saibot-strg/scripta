import Foundation

/// How a transcript with speakers is shown.
enum TranscriptStyle: String, CaseIterable, Identifiable {
    case text
    case bubbles

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .text: "Text"
        case .bubbles: "Sprechblasen"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .bubbles: "bubble.left.and.bubble.right"
        }
    }
}
