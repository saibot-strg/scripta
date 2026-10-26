import AppKit

/// A window reference that doesn't keep the window alive.
@MainActor
final class WeakWindow {
    weak var value: NSWindow?
}
