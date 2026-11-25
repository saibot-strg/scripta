import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Whether the window showing this view can be seen at all: false while it
    /// is minimized, on another Space or completely covered. Live displays
    /// (recording meters, pulsing dots) stop redrawing then, to save CPU.
    @Entry var isWindowVisible = true
}

extension View {
    /// Keeps `isWindowVisible` up to date for this view's window.
    func tracksWindowVisibility() -> some View {
        modifier(WindowVisibilityTracker())
    }
}

private struct WindowVisibilityTracker: ViewModifier {
    @State private var window = WeakWindow()
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.isWindowVisible, isVisible)
            .background(WindowReader { newWindow in
                window.value = newWindow
                // Not while SwiftUI is still adding the view.
                Task { update() }
            })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
                guard let changed = notification.object as? NSWindow, changed === window.value else { return }
                update()
            }
    }

    private func update() {
        let visible = window.value?.occlusionState.contains(.visible) ?? true
        if visible != isVisible {
            isVisible = visible
        }
    }
}
