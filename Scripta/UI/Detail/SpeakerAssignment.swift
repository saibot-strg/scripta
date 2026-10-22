import AVFoundation
import SwiftUI

/// A speaker's name above their text. A click opens `SegmentSpeakerChoices`
/// for this passage; a guessed name carries a "?", a click on it confirms.
struct SpeakerNameButton: View {
    @Environment(AppModel.self) private var appModel
    let segment: TranscriptSegment
    let speaker: SpeakerLabel
    let style: AnyShapeStyle
    /// Opens the assignment sheet for all of a speaker's passages.
    let onAssignAll: (SpeakerLabel) -> Void
    @State private var showsChoices = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showsChoices = true } label: {
                Text(speaker.displayName)
                    .foregroundStyle(style)
            }
            .buttonStyle(.plain)
            .help("Wem gehört diese Sprechblase?")
            .popover(isPresented: $showsChoices, arrowEdge: .bottom) {
                SegmentSpeakerChoices(segment: segment, onAssignAll: onAssignAll)
            }

            if speaker.isGuess(in: appModel.voices) {
                Button { appModel.confirmSuggestion(for: speaker) } label: {
                    Text(verbatim: "?")
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: .capsule)
                }
                .buttonStyle(.plain)
                .help("Vermutet – klicken zum Bestätigen, auf den Namen klicken zum Ändern")
            }
        }
    }
}

/// Small person button shown while hovering a passage; opens the same choices.
struct SegmentSpeakerButton: View {
    let segment: TranscriptSegment
    let onAssignAll: (SpeakerLabel) -> Void
    @State private var showsChoices = false

    var body: some View {
        Button("Sprecher dieser Sprechblase", systemImage: "person.crop.circle") { showsChoices = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Wem gehört diese Sprechblase?")
            .popover(isPresented: $showsChoices, arrowEdge: .bottom) {
                SegmentSpeakerChoices(segment: segment, onAssignAll: onAssignAll)
            }
    }
}

/// Who one passage belongs to. Choosing changes only this passage; the
/// last entry renames all passages of its speaker.
struct SegmentSpeakerChoices: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let segment: TranscriptSegment
    let onAssignAll: (SpeakerLabel) -> Void

    var body: some View {
        let current = segment.speaker
        let speakers = (segment.transcript?.speakers ?? [])
            .filter { $0.id != current?.id }
            .sorted { ($0.role == .me ? 0 : 1, $0.number) < ($1.role == .me ? 0 : 1, $1.number) }
        let present = Set((segment.transcript?.speakers ?? []).map { $0.displayName.lowercased() })
        let people = appModel.voices.people.filter { !present.contains($0.name.lowercased()) }

        VStack(alignment: .leading, spacing: 0) {
            Text("Diese Sprechblase gehört zu")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(speakers) { speaker in
                ChoiceRow(title: speaker.displayName, dot: speaker.tint) { choose { appModel.move(segment, to: speaker) } }
            }
            ForEach(people) { person in
                ChoiceRow(title: person.name, dot: .secondary) { choose { appModel.moveToNewSpeaker(segment, named: person.name) } }
            }
            ChoiceRow(title: String(localized: "Neuer Sprecher"), systemImage: "person.badge.plus") {
                choose { appModel.moveToNewSpeaker(segment) }
            }
            if let current {
                Divider().padding(.vertical, 4)
                if current.isGuess(in: appModel.voices) {
                    ChoiceRow(title: String(localized: "„\(current.displayName)“ bestätigen"), systemImage: "checkmark.circle") {
                        choose { appModel.confirmSuggestion(for: current) }
                    }
                }
                ChoiceRow(title: String(localized: "Alle von „\(current.displayName)“ benennen …"), systemImage: "person.2") {
                    choose { onAssignAll(current) }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(minWidth: 240)
    }

    private func choose(_ action: () -> Void) {
        action()
        dismiss()
    }
}

/// One entry of `SegmentSpeakerChoices`, highlighted on hover like a menu item.
private struct ChoiceRow: View {
    let title: String
    var dot: Color?
    var systemImage: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8).frame(width: 16)
                } else if let systemImage {
                    Image(systemName: systemImage).frame(width: 16)
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(isHovered ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension SpeakerLabel {
    /// The name was set from a guess and not confirmed yet.
    @MainActor
    func isGuess(in voices: VoiceLibrary) -> Bool {
        guard let status = voices.statuses[id], status.state == .suggested, let name = status.personName else { return false }
        return customName == name
    }
}

/// Above a transcript with unnamed voices: invites to assign them.
struct SpeakerBanner: View {
    @Environment(AppModel.self) private var appModel
    let transcript: Transcript
    let action: () -> Void

    var body: some View {
        let unnamed = transcript.speakers.filter { $0.role == .diarized && $0.customName == nil }
        let guessed = transcript.speakers.filter { $0.isGuess(in: appModel.voices) }
        if !unnamed.isEmpty || !guessed.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unnamed.isEmpty ? "\(guessed.count) Namen vermutet" : "\(unnamed.count) Stimmen ohne Namen")
                        .font(.headline)
                    Text(guessed.isEmpty
                         ? "Hör kurz rein und gib jeder Stimme einen Namen."
                         : "Vermutete Namen sind mit „?“ markiert. Hör rein und bestätige oder korrigiere sie.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Zuordnen …", action: action)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
        }
    }
}

/// "Wer spricht hier?": listen to each voice, name it, merge split voices.
struct SpeakerAssignmentSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.recognizesVoices) private var recognizesVoices = false
    let recording: Recording
    let transcript: Transcript

    @State private var names: [UUID: String] = [:]
    @State private var remembers: [UUID: Bool] = [:]
    @State private var excerpts = ExcerptPlayer()
    @State private var correctedCount: Int?

    /// Speakers in order of first appearance, "Ich" last.
    private var speakers: [SpeakerLabel] {
        var seen: Set<UUID> = []
        let ordered = transcript.orderedSegments.compactMap(\.speaker).filter { seen.insert($0.id).inserted }
        return ordered.filter { !$0.isLocalUser } + ordered.filter(\.isLocalUser)
    }

    var body: some View {
        let speakers = speakers
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wer spricht hier?")
                    .font(.title2.weight(.semibold))
                Text("Hör kurz rein und gib jeder Stimme einen Namen. Bekommen zwei Sprecher denselben Namen, werden sie zusammengeführt.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            if !recognizesVoices {
                optIn
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(speakers) { speaker in
                        row(speaker, among: speakers)
                        Divider()
                    }
                }
            }
            // A scroll view has no height of its own; show all rows up to a limit.
            .frame(height: min(CGFloat(speakers.count) * 104, 470))

            HStack {
                recount
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Fertig") {
                    apply(speakers)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 620)
        .onAppear {
            appModel.player.pause()
            for speaker in speakers {
                names[speaker.id] = speaker.displayName
                remembers[speaker.id] = true
            }
        }
        .onDisappear { excerpts.stop() }
    }

    /// Wrong number of voices (one person split up, two merged): transcribe
    /// again with the right number.
    private var recount: some View {
        let isMeeting = recording.source == .meeting
        return Menu(isMeeting ? "Anzahl der anderen korrigieren" : "Anzahl der Personen korrigieren") {
            ForEach(1...10, id: \.self) { count in
                Button("\(count)") { correctedCount = count }
            }
        }
        .fixedSize()
        .help(isMeeting
              ? "Wie viele Personen außer dir waren zu hören? Das Transkript wird mit genau so vielen Stimmen neu erstellt."
              : "Wie viele Personen waren zu hören? Das Transkript wird mit genau so vielen Stimmen neu erstellt.")
        .disabled(appModel.library.audioURL(for: recording) == nil)
        .confirmationDialog(
            "Mit \(correctedCount ?? 0) Stimmen neu erkennen?",
            isPresented: Binding(get: { correctedCount != nil }, set: { if !$0 { correctedCount = nil } })
        ) {
            Button("Neu erkennen") {
                if let correctedCount { appModel.transcribe(recording, speakerCount: correctedCount) }
                dismiss()
            }
        } message: {
            Text("Das Transkript wird neu erstellt; Textkorrekturen und Namen in diesem Transkript gehen verloren. Bekannte Stimmen schlägt Scripta wieder vor.")
        }
    }

    private var optIn: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("Stimmen wiedererkennen")
                    .font(.headline)
                Text("Scripta kann sich die Stimmen merken, die du benennst, und schlägt die Namen in späteren Aufnahmen vor. Stimmprofile sind biometrische Daten: Sie bleiben auf diesem Mac und lassen sich in den Einstellungen jederzeit löschen. Frag die Personen, ob das für sie in Ordnung ist.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einschalten") { recognizesVoices = true }
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private func row(_ speaker: SpeakerLabel, among speakers: [SpeakerLabel]) -> some View {
        let status = appModel.voices.statuses[speaker.id]
        let segments = speaker.segments.sorted { $0.end - $0.start > $1.end - $1.start }
        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(speaker.tint)
                .frame(width: 10, height: 10)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(speaker.defaultName, text: binding(for: speaker))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    choices(for: speaker, among: speakers)
                    if let name = status?.personName, status?.state == .suggested, names[speaker.id] != name {
                        Button("\(name)?") { names[speaker.id] = name }
                            .help("Klingt nach \(name) – klicken zum Übernehmen")
                    }
                    if status?.state == .suggested, names[speaker.id] == status?.personName {
                        Label("Vermutet", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if status?.state == .automatic {
                        Label("Erkannt", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let quote = segments.first?.text {
                    Text("„\(quote)“")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 16) {
                    Text("\(share(of: speaker), format: .percent.precision(.fractionLength(0))) der Redezeit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if recognizesVoices, status != nil {
                        Toggle("Stimme merken", isOn: rememberBinding(for: speaker))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .help("Aus: nur hier benennen, z. B. für Gäste")
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                appModel.player.pause()
                excerpts.toggle(
                    speaker.id,
                    url: appModel.library.audioURL(for: recording),
                    ranges: segments.prefix(3).map { ($0.start, min($0.end, $0.start + 8)) }
                )
            } label: {
                Image(systemName: excerpts.playingID == speaker.id ? "stop.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.bordered)
            .disabled(segments.isEmpty)
            .help("Reinhören (jeder Klick spielt eine andere Stelle)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Known people not in this meeting yet, and the other speakers of this
    /// meeting (choosing one merges). A known person who already is a speaker
    /// here appears only once, as a speaker: both would merge anyway.
    private func choices(for speaker: SpeakerLabel, among speakers: [SpeakerLabel]) -> some View {
        let others = speakers.filter { $0.id != speaker.id }
        let present = Set(others.map { (names[$0.id] ?? $0.displayName).lowercased() })
        let people = appModel.voices.people.filter { !present.contains($0.name.lowercased()) }
        return Menu {
            if !people.isEmpty {
                Section("Aus früheren Meetings") {
                    ForEach(people) { person in
                        Button(person.name) { names[speaker.id] = person.name }
                    }
                }
            }
            if !others.isEmpty {
                Section("Zusammenführen mit") {
                    ForEach(others) { other in
                        let name = names[other.id] ?? other.displayName
                        Button(name) { names[speaker.id] = name }
                    }
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Bekannte Person oder anderen Sprecher wählen")
    }

    private func binding(for speaker: SpeakerLabel) -> Binding<String> {
        Binding(get: { names[speaker.id] ?? speaker.displayName }, set: { names[speaker.id] = $0 })
    }

    private func rememberBinding(for speaker: SpeakerLabel) -> Binding<Bool> {
        Binding(get: { remembers[speaker.id] ?? true }, set: { remembers[speaker.id] = $0 })
    }

    private func share(of speaker: SpeakerLabel) -> Double {
        let total = transcript.segments.reduce(0) { $0 + $1.end - $1.start }
        guard total > 0 else { return 0 }
        return speaker.segments.reduce(0) { $0 + $1.end - $1.start } / total
    }

    /// Applies all names together, so swapping two names doesn't merge the
    /// speakers on the way.
    private func apply(_ speakers: [SpeakerLabel]) {
        let assignments = speakers.compactMap { speaker -> AppModel.NameAssignment? in
            guard let name = names[speaker.id] else { return nil }
            let remember = remembers[speaker.id] ?? true
            let status = appModel.voices.statuses[speaker.id]
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let isChanged = trimmed != speaker.displayName
            // Shown as recognized or guessed and left as is: the user confirmed it.
            let confirmsRecognition = (status?.state == .automatic || status?.state == .suggested) && trimmed == status?.personName
            let forgets = !remember && status?.personID != nil
            guard isChanged || confirmsRecognition || forgets else { return nil }
            return AppModel.NameAssignment(speaker: speaker, name: trimmed, remember: remember)
        }
        appModel.assignNames(assignments, in: transcript)
    }
}

/// Plays short excerpts of one speaker; each start plays the next excerpt.
@MainActor
@Observable
final class ExcerptPlayer {
    private(set) var playingID: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var nextIndex: [UUID: Int] = [:]

    func toggle(_ id: UUID, url: URL?, ranges: [(start: TimeInterval, end: TimeInterval)]) {
        let wasPlaying = playingID == id
        stop()
        guard !wasPlaying, let url, !ranges.isEmpty, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        let index = (nextIndex[id] ?? 0) % ranges.count
        nextIndex[id] = index + 1
        let range = ranges[index]
        player.currentTime = range.start
        guard player.play() else { return }
        self.player = player
        playingID = id
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(range.end - range.start, 1)))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playingID = nil
    }
}
