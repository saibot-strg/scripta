import AppKit

/// Handles app lifecycle events SwiftUI doesn't expose.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.current.apply()
        // Remember the language this instance runs in, before the settings change it.
        _ = AppLanguage.atLaunch
        // Scripta keeps working without a window (dictation shortcut, menu bar,
        // recordings), so macOS must not quit it when it looks idle.
        ProcessInfo.processInfo.disableAutomaticTermination("Dictation and recordings run in the background")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    /// Closing the window doesn't quit the app (dictation keeps working).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Close an active recording cleanly; see stopRecordingForTermination().
        appModel?.stopRecordingForTermination()
        return .terminateNow
    }
}
