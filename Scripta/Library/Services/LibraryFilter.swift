import Foundation
import SwiftData

/// Sidebar entries that filter the library.
enum LibraryFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case microphone
    case meetings
    case imports
    case notTranscribed
    case inProgress
    case done
    case failed

    var id: String { rawValue }

    static let libraryFilters: [LibraryFilter] = [.all]
    static let sourceFilters: [LibraryFilter] = [.microphone, .meetings, .imports]
    static let statusFilters: [LibraryFilter] = [.notTranscribed, .inProgress, .done, .failed]

    var title: LocalizedStringResource {
        switch self {
        case .all: "Alle Aufnahmen"
        case .microphone: "Mikrofon"
        case .meetings: "Meetings"
        case .imports: "Importiert"
        case .notTranscribed: "Nicht transkribiert"
        case .inProgress: "In Bearbeitung"
        case .done: "Fertig"
        case .failed: "Fehler"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "waveform"
        case .microphone: RecordingSource.microphone.systemImage
        case .meetings: RecordingSource.meeting.systemImage
        case .imports: RecordingSource.importedFile.systemImage
        case .notTranscribed: TranscriptionStatus.notTranscribed.systemImage
        case .inProgress: "hourglass"
        case .done: TranscriptionStatus.done.systemImage
        case .failed: TranscriptionStatus.failed.systemImage
        }
    }

    func matches(_ recording: Recording) -> Bool {
        switch self {
        case .all: true
        case .microphone: recording.source == .microphone
        case .meetings: recording.source == .meeting
        case .imports: recording.source == .importedFile
        case .notTranscribed: recording.status == .notTranscribed
        case .inProgress: recording.status.isInProgress
        case .done: recording.status == .done
        case .failed: recording.status == .failed
        }
    }
}

/// Sort options of the recording list.
enum LibrarySortField: String, CaseIterable, Identifiable, Sendable {
    case date
    case title
    case duration

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .date: "Datum"
        case .title: "Titel"
        case .duration: "Dauer"
        }
    }

    func descriptors(ascending: Bool) -> [SortDescriptor<Recording>] {
        let order: SortOrder = ascending ? .forward : .reverse
        return switch self {
        case .date:
            [SortDescriptor(\Recording.createdAt, order: order)]
        case .title:
            [SortDescriptor(\Recording.title, comparator: .localizedStandard, order: order),
             SortDescriptor(\Recording.createdAt, order: .reverse)]
        case .duration:
            [SortDescriptor(\Recording.duration, order: order),
             SortDescriptor(\Recording.createdAt, order: .reverse)]
        }
    }
}
