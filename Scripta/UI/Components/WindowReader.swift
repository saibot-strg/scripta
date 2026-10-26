import AppKit
import SwiftUI

/// Reports the window that hosts a SwiftUI view.
struct WindowReader: NSViewRepresentable {
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
