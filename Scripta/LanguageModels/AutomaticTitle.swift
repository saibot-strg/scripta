import Foundation

/// Decides when Scripta may replace a recording's title by one written by
/// the language model: never once the user named the recording.
struct AutomaticTitle {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "Titel automatisch vorschlagen" (on by default).
    var isEnabled: Bool {
        defaults.object(forKey: SettingsKey.suggestsTitles) as? Bool ?? true
    }

    /// After a transcription: the first transcript of a recording the user
    /// hasn't renamed, or a later one while the title is still the generated
    /// "Aufnahme …"/"Meeting …" (older recordings, renamed or not, can't be
    /// told apart otherwise).
    func applies(to recording: Recording, isFirstTranscript: Bool) -> Bool {
        guard !userTitledIDs.contains(recording.id) else { return false }
        return isFirstTranscript || Self.looksGenerated(recording.title)
    }

    /// "Aufnahme 26. Okt. 2026, 11:13", "Meeting Discord 22. Okt. 2026, 15:26",
    /// "Recording Oct 26, 2026 at 11:13 AM".
    static func looksGenerated(_ title: String) -> Bool {
        guard ["Aufnahme ", "Meeting ", "Recording "].contains(where: title.hasPrefix) else { return false }
        return title.contains(/\b20\d\d\b/) && title.contains(/\d{1,2}[:.]\d\d/)
    }

    var userTitledIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: SettingsKey.userTitledRecordings) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// The user gave the recording a title.
    func markUserTitled(_ id: UUID) {
        var ids = userTitledIDs
        guard ids.insert(id).inserted else { return }
        save(ids)
    }

    /// The recording was deleted.
    func forget(_ id: UUID) {
        var ids = userTitledIDs
        guard ids.remove(id) != nil else { return }
        save(ids)
    }

    private func save(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString).sorted(), forKey: SettingsKey.userTitledRecordings)
    }
}
