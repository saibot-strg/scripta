import AppKit
import SwiftUI

/// Floating pill near the bottom of the screen while dictating. A
/// non-activating panel that never becomes key, so the text field the user
/// is typing into keeps its focus.
@MainActor
final class DictationHUD {
    private var panel: HUDPanel?
    private let presentation = HUDPresentation()
    private var hideTask: Task<Void, Never>?

    /// The pill animates in and out itself; this long after hiding it, the
    /// panel can be taken off screen.
    private static let exitDuration: Duration = .milliseconds(320)

    func show(_ controller: DictationController) {
        hideTask?.cancel()
        let panel = panel ?? HUDPanel(rootView: DictationHUDView(controller: controller, presentation: presentation))
        self.panel = panel
        if !panel.isVisible {
            position(panel)
            panel.orderFrontRegardless()
        }
        // On the next run loop pass, so a freshly created view first draws
        // its hidden state and then animates in.
        Task { [presentation] in presentation.isShown = true }
    }

    func hide(after delay: Duration = .zero, completion: @escaping @MainActor () -> Void = {}) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let panel else { return }
            // Leaves the way it came in (see DictationHUDView).
            presentation.isShown = false
            try? await Task.sleep(for: Self.exitDuration)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            completion()
        }
    }

    /// Bottom center of the screen with the mouse pointer, above the Dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48))
    }
}
