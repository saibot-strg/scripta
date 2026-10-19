import Foundation
import SwiftData
import Testing
@testable import Scripta

@MainActor
@Suite("Library filters and sorting")
struct LibraryFilterTests {
    let container = ModelContainerFactory.makeInMemory()
    var context: ModelContext { container.mainContext }

    @Test("Every filter except 'all' is listed in exactly one sidebar section")
    func sidebarSections() {
        let listed = LibraryFilter.libraryFilters + LibraryFilter.sourceFilters + LibraryFilter.statusFilters
        #expect(Set(listed) == Set(LibraryFilter.allCases))
        #expect(listed.count == LibraryFilter.allCases.count)
    }

    @Test("Source filters match only their source", arguments: [
        (LibraryFilter.microphone, RecordingSource.microphone),
        (.meetings, .meeting),
        (.imports, .importedFile),
    ])
    func sourceFilters(filter: LibraryFilter, source: RecordingSource) {
        for candidate in RecordingSource.allCases {
            let recording = Recording(title: "x", source: candidate)
            #expect(filter.matches(recording) == (candidate == source))
            #expect(LibraryFilter.all.matches(recording))
        }
    }

    @Test("'In Bearbeitung' covers queued and running")
    func inProgressFilter() {
        let matching = TranscriptionStatus.allCases.filter {
            LibraryFilter.inProgress.matches(Recording(title: "x", source: .microphone, status: $0))
        }
        #expect(Set(matching) == [.queued, .running])
    }

    @Test("Status filters partition all recordings")
    func statusPartition() {
        for status in TranscriptionStatus.allCases {
            let recording = Recording(title: "x", source: .microphone, status: status)
            let hits = LibraryFilter.statusFilters.filter { $0.matches(recording) }
            #expect(hits.count == 1, "status \(status) matched \(hits)")
        }
    }

    @Test("Sort descriptors order by date, title and duration")
    func sorting() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(Recording(title: "banane", createdAt: base, duration: 30, source: .microphone))
        context.insert(Recording(title: "Apfel", createdAt: base.addingTimeInterval(60), duration: 10, source: .microphone))
        context.insert(Recording(title: "Äpfel", createdAt: base.addingTimeInterval(120), duration: 20, source: .microphone))
        try context.save()

        func titles(_ field: LibrarySortField, ascending: Bool) throws -> [String] {
            try context.fetch(FetchDescriptor(sortBy: field.descriptors(ascending: ascending))).map(\.title)
        }

        #expect(try titles(.date, ascending: false) == ["Äpfel", "Apfel", "banane"])
        #expect(try titles(.duration, ascending: true) == ["Apfel", "Äpfel", "banane"])
        // Localized standard comparison: case-insensitive, umlauts next to their base letter.
        #expect(try titles(.title, ascending: true).last == "banane")
    }
}
