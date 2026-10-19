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
}
