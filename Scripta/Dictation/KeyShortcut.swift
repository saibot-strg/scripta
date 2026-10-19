import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus modifiers, stored in Carbon terms
/// because global hotkeys are registered through Carbon.
struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌃⌥Space: free in macOS by default. ⌥Space is taken by apps like
    /// Alfred or ChatGPT, ⌘Space by Spotlight.
    static let defaultDictation = KeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// From a key press, e.g. in the shortcut recorder. Returns nil for keys
    /// that make poor global shortcuts (no ⌘, ⌥ or ⌃, unless it's an F-key).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let isFunctionKey = Self.functionKeys.keys.contains(Int(event.keyCode))
        let hasStrongModifier = modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        guard hasStrongModifier || isFunctionKey else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    /// Like macOS menus: "⌃⌥Leertaste".
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(for: Int(keyCode))
    }

    // MARK: - Key names

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func keyName(for keyCode: Int) -> String {
        if let name = functionKeys[keyCode] { return name }
        switch keyCode {
        case kVK_Space: return String(localized: "Leertaste")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
        }
    }

    /// The character a key produces on the current keyboard layout.
    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

extension KeyShortcut {
    /// Stored as JSON in UserDefaults.
    static func load(forKey key: String) -> KeyShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyShortcut.self, from: data)
    }

    func save(forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: key)
    }
}
