import Foundation

extension TextInserter.Result {
    var isSuccess: Bool { self == .inserted || self == .pasted }

    var symbol: String {
        isSuccess ? "checkmark.circle.fill" : "doc.on.clipboard"
    }

    var message: String {
        switch self {
        case .inserted, .pasted:
            String(localized: "Eingefügt")
        case .copiedToClipboard:
            String(localized: "In der Zwischenablage – zum Einfügen ⌘V drücken")
        case .blockedBySecureInput:
            String(localized: "Passwortfeld aktiv – Text liegt in der Zwischenablage")
        }
    }
}
