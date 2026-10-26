import AppKit

/// Light or dark appearance, independent of the system setting if wanted.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .system: "Wie System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: SettingsKey.appearance).flatMap(AppAppearance.init) ?? .system
    }

    /// Applies to every window, the dictation HUD and the settings.
    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
