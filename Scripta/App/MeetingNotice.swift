import AppKit

/// Before the first meeting recording: a reminder to tell the other people
/// that they are being recorded. Shown until the user confirms it once.
@MainActor
struct MeetingNotice {
    var defaults: UserDefaults = .standard
    /// Shows the notice; true means "record".
    var present: @MainActor () async -> Bool = MeetingNotice.showAlert

    /// True if the meeting may start: confirmed now or at an earlier meeting.
    func confirm() async -> Bool {
        guard !defaults.bool(forKey: SettingsKey.meetingNoticeConfirmed) else { return true }
        guard await present() else { return false }
        defaults.set(true, forKey: SettingsKey.meetingNoticeConfirmed)
        return true
    }

    /// As a sheet on the main window, or as its own alert when the meeting
    /// is started from the menu bar.
    static func showAlert() async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Sag den anderen, dass du aufnimmst")
        alert.informativeText = String(localized: "Scripta nimmt dich und alle anderen im Meeting auf. Sag den Teilnehmenden zu Beginn, dass du das Gespräch aufzeichnest, und hol ihr Einverständnis ein. In vielen Ländern, auch in Deutschland, ist es verboten, Gespräche ohne Zustimmung aufzunehmen.")
        alert.addButton(withTitle: String(localized: "Verstanden, Aufnahme starten"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        NSApp.activate()
        let response = if let window = NSApp.keyWindow, window.isVisible, window.attachedSheet == nil {
            await alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        return response == .alertFirstButtonReturn
    }
}
