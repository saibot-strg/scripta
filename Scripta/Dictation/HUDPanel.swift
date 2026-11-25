import AppKit
import SwiftUI

/// Borderless, non-activating panel for the dictation pill: never key, never
/// in the window cycle, on every Space and above full-screen apps.
final class HUDPanel: NSPanel {
    /// Room for the widest pill (a message); the panel itself is invisible.
    static let size = CGSize(width: 320, height: 80)

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
