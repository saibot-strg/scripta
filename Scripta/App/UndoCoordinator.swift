import Foundation

/// ⌘Z for the user's own edits.
///
/// Each user action registers how to reverse itself in the main window's
/// undo manager, so the Edit menu lists it in order with text field edits.
/// Reversing registers the way back again, which becomes Redo.
///
/// SwiftData's own undo support is deliberately not used: with an undo
/// manager attached to a context, deleting a recording (cascading to its
/// transcript) traps in SwiftData, even with registration switched off.
@MainActor
final class UndoCoordinator {
    private(set) weak var manager: UndoManager?

    /// Uses the main window's undo manager from now on; nil turns undo off.
    func attach(_ manager: UndoManager?) {
        guard manager !== self.manager else { return }
        clear()
        self.manager = manager
    }

    /// Registers `reverse` as one step named `actionName` ("Undo Rename").
    /// While undoing, this is the redo step.
    func register(_ actionName: String, reverse: @escaping @MainActor () -> Void) {
        guard let manager else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { _ in
            MainActor.assumeIsolated { reverse() }
        }
        manager.setActionName(actionName)
        manager.endUndoGrouping()
    }

    /// Forgets all steps, e.g. after deleting what they refer to.
    func clear() {
        manager?.removeAllActions(withTarget: self)
    }
}
