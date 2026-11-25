import Foundation

/// The levelling gain last measured for each microphone (by device UID).
///
/// A dictation is too short to measure how quiet a microphone is before its
/// meter has to show something; with the gain remembered from the last
/// recording or dictation, a quiet headset is shown raised from the start.
enum MicrophoneGainMemory {
    static let key = "recording.microphoneGains"

    static func gain(forDevice uid: String?, defaults: UserDefaults = .standard) -> Float? {
        guard let uid, let gains = defaults.dictionary(forKey: key), let gain = gains[uid] as? Double else { return nil }
        return Float(gain)
    }

    static func remember(_ gain: Float, forDevice uid: String?, defaults: UserDefaults = .standard) {
        guard let uid else { return }
        var gains = defaults.dictionary(forKey: key) ?? [:]
        gains[uid] = Double(gain)
        defaults.set(gains, forKey: key)
    }
}
