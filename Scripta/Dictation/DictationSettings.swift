import Foundation

/// Dictation preferences (UserDefaults).
enum DictationSettings {
    static let enabledKey = "dictation.enabled"
    static let modeKey = "dictation.mode"
    static let shortcutKey = "dictation.shortcut"
    static let appendsSpaceKey = "dictation.appendsSpace"
    /// A short sound when dictation starts and stops (off by default).
    static let playsSoundsKey = "dictation.sounds"
    /// Leaves the dictated text on the clipboard instead of restoring the
    /// previous contents, so it isn't lost when no text field had focus (off by default).
    static let keepsOnClipboardKey = "dictation.keepsOnClipboard"
    /// Spoken punctuation and line breaks ("Komma", "neue Zeile", "question mark"), on by default.
    static let usesVoiceCommandsKey = "dictation.voiceCommands"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var mode: DictationController.Mode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(DictationController.Mode.init) ?? .hold
    }

    static var shortcut: KeyShortcut {
        get { KeyShortcut.load(forKey: shortcutKey) ?? .defaultDictation }
        set { newValue.save(forKey: shortcutKey) }
    }

    static var appendsSpace: Bool {
        UserDefaults.standard.object(forKey: appendsSpaceKey) as? Bool ?? true
    }

    static var playsSounds: Bool { UserDefaults.standard.bool(forKey: playsSoundsKey) }

    static var keepsOnClipboard: Bool { UserDefaults.standard.bool(forKey: keepsOnClipboardKey) }

    static var usesVoiceCommands: Bool {
        UserDefaults.standard.object(forKey: usesVoiceCommandsKey) as? Bool ?? true
    }
}
