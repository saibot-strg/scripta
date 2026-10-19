import AppKit
import SwiftUI

extension View {
    /// Space toggles playback in this window unless a text field has focus.
    ///
    /// A menu shortcut can't be used: a plain Space key equivalent would also
    /// swallow spaces typed into text fields.
    func playbackSpaceShortcut(_ player: PlayerModel) -> some View {
        modifier(PlaybackSpaceShortcut(player: player))
    }
}

private struct PlaybackSpaceShortcut: ViewModifier {
    let player: PlayerModel
    @State private var window = WeakWindow()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window.value = $0 })
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handle(event)
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let spaceKeyCode: UInt16 = 49
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard event.keyCode == spaceKeyCode, modifiers.isEmpty,
              let keyWindow = NSApp.keyWindow, keyWindow === window.value,
              keyWindow.attachedSheet == nil,
              !(keyWindow.firstResponder is NSText),
              player.isAvailable else { return event }
        if !event.isARepeat {
            player.togglePlayPause()
        }
        return nil
    }
}

@MainActor
private final class WeakWindow {
    weak var value: NSWindow?
}

/// Reports the window that hosts a SwiftUI view.
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onWindowChange = onChange
    }

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
