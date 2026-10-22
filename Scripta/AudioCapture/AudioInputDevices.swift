import CoreAudio
import os

/// A microphone or other audio input.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let uid: String
    let name: String
    var id: String { uid }
}

enum AudioInputDevices {
    /// All devices with at least one input stream.
    static func available() -> [AudioInputDevice] {
        let devices = (try? AudioHardwareSystem.shared.devices) ?? []
        return devices.compactMap { device in
            let streams = (try? device.streams) ?? []
            guard streams.contains(where: { (try? $0.direction) == .input }),
                  let uid = try? device.uid, let name = try? device.name else { return nil }
            return AudioInputDevice(uid: uid, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The Core Audio ID of the device chosen in the settings, if it is connected.
    static func selectedDeviceID() -> AudioObjectID? {
        guard let uid = RecordingSettings.microphoneUID,
              let device = try? AudioHardwareSystem.shared.device(forUID: uid) else { return nil }
        return device.id
    }

    /// The system's default input, used when no microphone is chosen or the
    /// chosen one isn't connected.
    static func defaultDevice() -> AudioInputDevice? {
        guard let device = try? AudioHardwareSystem.shared.defaultInputDevice,
              let uid = try? device.uid, let name = try? device.name else { return nil }
        return AudioInputDevice(uid: uid, name: name)
    }
}

/// Calls back on the main thread whenever an audio device is connected or
/// disconnected or the default input changes. Stops when released.
final class AudioDeviceObservation {
    private static let addresses = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice].map {
        AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private let listener: AudioObjectPropertyListenerBlock

    init(onChange: @escaping @MainActor () -> Void) {
        listener = { _, _ in MainActor.assumeIsolated { onChange() } }
        for var address in Self.addresses {
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            if status != noErr {
                Logger.recording.error("Could not observe audio devices: \(status)")
            }
        }
    }

    deinit {
        for var address in Self.addresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }
}
