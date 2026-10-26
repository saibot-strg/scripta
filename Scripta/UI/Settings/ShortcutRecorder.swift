import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new shortcut (Esc cancels).
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut
    var onRecordingChange: (Bool) -> Void = { _ in }
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? String(localized: "Kürzel drücken …") : shortcut.displayString)
                .frame(minWidth: 130)
                .monospaced(!isRecording)
        }
        .help("Klicken und neues Tastenkürzel drücken. Mindestens ⌘, ⌥ oder ⌃ (oder eine F-Taste).")
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let newShortcut = KeyShortcut(event: event) {
                shortcut = newShortcut
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
