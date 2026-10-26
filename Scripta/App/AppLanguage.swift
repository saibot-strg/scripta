import AppKit

/// The language of Scripta's interface, independent of the system language.
///
/// Stored the way macOS stores a per-app language (System Settings ›
/// General › Language & Region › Applications): as `AppleLanguages` in the
/// app's own defaults. It takes effect at the next launch.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    /// Each language in its own name, like the system's language lists
    /// (never translated); nil for `.system`.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// The choice stored in the app's defaults (not the system's list).
    static func stored(in defaults: UserDefaults = .standard, bundleID: String? = Bundle.main.bundleIdentifier) -> AppLanguage {
        guard let bundleID,
              let languages = defaults.persistentDomain(forName: bundleID)?[SettingsKey.appleLanguages] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    func store(in defaults: UserDefaults = .standard) {
        switch self {
        case .system: defaults.removeObject(forKey: SettingsKey.appleLanguages)
        case .german, .english: defaults.set([rawValue], forKey: SettingsKey.appleLanguages)
        }
    }

    /// The choice when this instance launched (what it shows now). Read on
    /// first use, which is before the settings can change it.
    static let atLaunch = stored()
}
