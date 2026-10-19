import SwiftUI

/// How a transcript with speakers is shown.
enum TranscriptStyle: String, CaseIterable, Identifiable {
    case text
    case bubbles

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .text: "Text"
        case .bubbles: "Sprechblasen"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .bubbles: "bubble.left.and.bubble.right"
        }
    }
}

/// Detail column: header, transcript (or its status) and the floating player.
struct RecordingDetailView: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording
    @AppStorage("detail.transcriptStyle") private var transcriptStyle: TranscriptStyle = .bubbles
    @State private var timeline = TranscriptTimeline.empty
    @State private var activeSegmentID: UUID?
    @State private var speakerToRename: SpeakerLabel?
    @State private var speakerName = ""

    var body: some View {
        let transcript = recording.transcript
        let hasSpeakers = transcript?.hasSpeakers ?? false
        let showsStatus = transcript == nil || recording.status != .done

        ScrollViewReader { proxy in
            ScrollView {
                // One lazy stack for header and segments, so long transcripts only
                // build the rows that are visible.
                LazyVStack(alignment: .leading, spacing: 0) {
                    DetailHeaderView(recording: recording)
                        .padding(.bottom, 28)

                    if showsStatus {
                        TranscriptStatusCard(recording: recording)
                            .padding(.bottom, transcript == nil ? 0 : 28)
                    }

                    if let transcript {
                        TranscriptView(
                            transcript: transcript,
                            style: hasSpeakers ? transcriptStyle : .text,
                            activeSegmentID: activeSegmentID,
                            onSelect: { segment in
                                appModel.player.seek(to: segment.start)
                                if !appModel.player.isPlaying { appModel.player.play() }
                            },
                            onRenameSpeaker: { speaker in
                                speakerName = speaker.displayName
                                speakerToRename = speaker
                            }
                        )
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: activeSegmentID) { _, id in
                // Follow playback, but leave the scroll position alone when paused.
                guard let id, appModel.player.isPlaying else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background {
            PlaybackFollower(timeline: timeline, activeSegmentID: $activeSegmentID)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .toolbar {
            ToolbarItem {
                transcribeButton
            }
            if hasSpeakers {
                ToolbarItem {
                    Picker("Darstellung", selection: $transcriptStyle) {
                        ForEach(TranscriptStyle.allCases) { style in
                            Label { Text(style.label) } icon: { Image(systemName: style.systemImage) }
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Darstellung des Transkripts")
                }
            }
            ToolbarItem {
                Menu("Exportieren", systemImage: "square.and.arrow.up") {
                    ExportMenuItems(recording: recording)
                }
                .disabled(transcript?.segments.isEmpty ?? true)
                .help("Transkript exportieren, kopieren oder teilen")
            }
        }
        .alert("Sprecher umbenennen", isPresented: Binding(
            get: { speakerToRename != nil },
            set: { if !$0 { speakerToRename = nil } }
        )) {
            TextField("Name", text: $speakerName)
            Button("Umbenennen") {
                if let speakerToRename { appModel.rename(speakerToRename, to: speakerName) }
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gilt für alle Abschnitte dieses Sprechers. Leer lassen für den Standardnamen.")
        }
        .task(id: recording.id) {
            appModel.loadPlayer(for: recording)
        }
        .task(id: transcript?.modifiedAt) {
            timeline = TranscriptTimeline(recording.transcript)
        }
        // Reset scroll position and local state when the selection changes.
        .id(recording.id)
    }

    @ViewBuilder
    private var transcribeButton: some View {
        switch recording.status {
        case .queued, .running:
            Button("Transkription abbrechen", systemImage: "xmark.circle") {
                appModel.cancelTranscription(of: recording)
            }
            .help("Transkription abbrechen")
        case .done:
            Button("Erneut transkribieren", systemImage: "arrow.clockwise") {
                appModel.transcribe(recording)
            }
            .help("Transkript neu erstellen (Korrekturen gehen verloren)")
            .disabled(appModel.library.audioURL(for: recording) == nil)
        case .notTranscribed, .failed:
            Button("Transkribieren", systemImage: "text.bubble") {
                appModel.transcribe(recording)
            }
            .help("Lokal mit Parakeet transkribieren")
            .disabled(appModel.library.audioURL(for: recording) == nil)
        }
    }
}

#if DEBUG
#Preview(traits: .sampleLibrary) {
    @Previewable @Environment(AppModel.self) var appModel
    RecordingDetailView(recording: SampleData.firstMeeting(in: appModel.library.modelContext))
        .frame(width: 760, height: 700)
}
#endif
