import Foundation
import os

/// Where recordings live: the app container by default, or a folder the user
/// chose (e.g. in iCloud Drive or on an external disk).
///
/// A chosen folder is remembered as a security-scoped bookmark, the only way a
/// sandboxed app keeps access across launches. Each recording stores the
/// bookmark of the folder it was saved to, so changing the location later
/// doesn't break older recordings.
@MainActor
@Observable
final class StorageLocations {
    static let bookmarkKey = "storage.bookmark"

    /// Storage for new recordings.
    private(set) var current: RecordingStorage
    /// Bookmark of `current`; nil for the default location.
    private(set) var currentBookmark: Data?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let defaultStorage: RecordingStorage
    @ObservationIgnored private var resolvedRoots: [Data: URL] = [:]

    init(defaults: UserDefaults = .standard, defaultStorage: RecordingStorage = RecordingStorage()) {
        self.defaults = defaults
        self.defaultStorage = defaultStorage
        current = defaultStorage
        if let bookmark = defaults.data(forKey: Self.bookmarkKey), let url = resolve(bookmark) {
            current = RecordingStorage(rootURL: url)
            currentBookmark = bookmark
        }
    }

    /// For tests and previews: always the given storage.
    init(fixed storage: RecordingStorage) {
        defaults = UserDefaults(suiteName: "StorageLocations.fixed") ?? .standard
        defaultStorage = storage
        current = storage
    }

    var isDefault: Bool { currentBookmark == nil }

    /// Storage of a recording saved with the given bookmark (nil = default).
    func storage(forBookmark bookmark: Data?) -> RecordingStorage {
        guard let bookmark else { return defaultStorage }
        if bookmark == currentBookmark { return current }
        guard let url = resolve(bookmark) else { return defaultStorage }
        return RecordingStorage(rootURL: url)
    }

    /// Every location that may hold recordings (for crash recovery).
    var allLocations: [(storage: RecordingStorage, bookmark: Data?)] {
        var locations: [(RecordingStorage, Data?)] = [(defaultStorage, nil)]
        if let currentBookmark { locations.append((current, currentBookmark)) }
        return locations
    }

    /// New recordings go to `folder` from now on.
    func use(_ folder: URL) throws {
        let isScoped = folder.startAccessingSecurityScopedResource()
        defer { if isScoped { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard let url = resolve(bookmark) else { throw CocoaError(.fileReadNoPermission) }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        current = RecordingStorage(rootURL: url)
        currentBookmark = bookmark
        Logger.storage.notice("Storage location changed")
    }

    func useDefault() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        current = defaultStorage
        currentBookmark = nil
    }

    /// Resolves a bookmark once and keeps access for the app's lifetime.
    private func resolve(_ bookmark: Data) -> URL? {
        if let url = resolvedRoots[bookmark] { return url }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            Logger.storage.error("Storage folder is no longer accessible")
            return nil
        }
        resolvedRoots[bookmark] = url
        return url
    }
}
