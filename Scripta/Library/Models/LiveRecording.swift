import Foundation

/// A recording that is still running or being saved, shown at the top of the
/// list before it is in the library. Its `id` is the library recording's ID
/// once saved, so the selection carries over.
struct LiveRecording: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let source: RecordingSource
    var isSaving = false
}

extension SidebarItem {
    /// Live recordings appear under "Alle Aufnahmen" and their source filter.
    func matches(_ live: LiveRecording) -> Bool {
        switch self {
        case .filter(.all): true
        case .filter(.microphone): live.source == .microphone
        case .filter(.meetings): live.source == .meeting
        case .filter, .folder: false
        }
    }
}
