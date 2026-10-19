import AppKit
import Carbon.HIToolbox
import os

/// System-wide hotkeys through Carbon's `RegisterEventHotKey`.
///
/// Works inside the App Sandbox without any permission, swallows the key
/// combination (it isn't typed into the frontmost app) and reports both press
/// and release, which push-to-talk needs.
@MainActor
final class HotKeyCenter {
    enum HotKeyError: LocalizedError {
        case unavailable(OSStatus)

        var errorDescription: String? {
            String(localized: "Das Tastenkürzel ist bereits von einer anderen App belegt oder nicht erlaubt.")
        }
    }

    private struct Registration {
        let reference: EventHotKeyRef
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    /// Four-character signature that marks Scripta's hotkeys ("SCRP").
    private static let signature: OSType = 0x5343_5250

    func register(
        _ shortcut: KeyShortcut,
        id: UInt32,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void = {}
    ) throws(HotKeyError) {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else {
            Logger.dictation.error("Hotkey \(shortcut.displayString, privacy: .public) unavailable: \(status)")
            throw .unavailable(status)
        }
        registrations[id] = Registration(reference: reference, onPress: onPress, onRelease: onRelease)
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.reference)
    }

    fileprivate func handle(id: UInt32, isPress: Bool) {
        guard let registration = registrations[id] else { return }
        isPress ? registration.onPress() : registration.onRelease()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // The center lives as long as the app, so an unretained pointer is safe.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, eventTypes.count, &eventTypes, userData, &eventHandler)
    }
}

/// Carbon callback; delivered on the main thread.
private func hotKeyEventHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = hotKeyID.id
    // Pass the pointer as an integer: raw pointers aren't Sendable.
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKeyCenter>.fromOpaque(pointer).takeUnretainedValue().handle(id: id, isPress: isPress)
    }
    return noErr
}
