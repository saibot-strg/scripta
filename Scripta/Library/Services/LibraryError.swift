import Foundation

/// Errors of the library layer with user-facing German descriptions.
enum LibraryError: LocalizedError {
    case storeUnavailable(underlying: any Error)
    case saveFailed(underlying: any Error)
    case fileRemovalFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            String(localized: "Die Bibliothek konnte nicht geöffnet werden.")
        case .saveFailed:
            String(localized: "Die Änderung konnte nicht gespeichert werden.")
        case .fileRemovalFailed:
            String(localized: "Die Audiodateien konnten nicht gelöscht werden.")
        }
    }

    var failureReason: String? {
        switch self {
        case .storeUnavailable(let error), .saveFailed(let error), .fileRemovalFailed(let error):
            error.localizedDescription
        }
    }
}

/// An error or notice prepared for display in an alert.
struct PresentableError: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    /// Privacy pane in System Settings that resolves the problem, if any.
    var settingsURL: URL?

    init(_ error: any Error) {
        let localized = error as? LocalizedError
        title = localized?.errorDescription ?? error.localizedDescription
        message = [localized?.failureReason, localized?.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")
            .nilIfEmpty
        settingsURL = (error as? any PrivacySettingsLinking)?.privacySettingsURL
    }

    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
