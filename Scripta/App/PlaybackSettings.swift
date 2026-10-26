import Foundation

/// Playback preferences (UserDefaults).
enum PlaybackSettings {
    static var rate: Float {
        get {
            let stored = UserDefaults.standard.float(forKey: SettingsKey.playbackRate)
            return PlayerModel.rates.contains(stored) ? stored : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.playbackRate) }
    }
}
