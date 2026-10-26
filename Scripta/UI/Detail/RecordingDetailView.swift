import SwiftUI

/// Detail column: header, transcript (or its status) and the floating player.
struct RecordingDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recording: Recording
    @AppStorage("detail.transcriptStyle") private var transcriptStyle: TranscriptStyle = .bubbles
    @State private var layout = TranscriptLayout.empty
    @State private var activeSegmentID: UUID?
    @State private var isAssigningSpeakers = false
    /// Checked once per recording (the files may be on a slow or unavailable
    /// volume); assumed until then, so no "no audio file" note flashes up.
    @State private var hasAudio = true

    var body: some View {
        let transcript = recording.transcript
        let hasSpeakers = transcript?.hasSpeakers ?? false
        let showsStatus = transcript == nil || recording.status != .done
        // Right after an edit the cached layout is one step behind; build
        // a fresh one for this pass instead of showing stale rows.
        let rows = transcript.map { layout.isCurrent(for: $0) ? layout.rows : TranscriptLayout($0).rows } ?? []

        ScrollViewReader { proxy in
            ScrollView {
                // One lazy stack for header and segments, so long transcripts only
                // build the rows that are visible.
                LazyVStack(alignment: .leading, spacing: 0) {
                    DetailHeaderView(recording: recording)
                        .padding(.bottom, 28)

                    if showsStatus {
                        TranscriptStatusCard(recording: recording, hasAudio: hasAudio)
                            .padding(.bottom, transcript == nil ? 0 : 28)
                    }

                    if let transcript, recording.status == .done {
                        SpeakerBanner(transcript: transcript) { isAssigningSpeakers = true }
                            .padding(.bottom, 24)
                    }

                    TranscriptView(
                        rows: rows,
                        style: hasSpeakers ? transcriptStyle : .text,
                        activeSegmentID: activeSegmentID,
                        onSelect: play,
                        onRenameSpeaker: { _ in isAssigningSpeakers = true }
                    )
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
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background {
            PlaybackFollower(timeline: layout.timeline, activeSegmentID: $activeSegmentID)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .toolbar {
            ToolbarItem {
                TranscribeToolbarButton(recording: recording, hasAudio: hasAudio)
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
                .disabled(rows.isEmpty)
                .help("Transkript exportieren, kopieren oder teilen")
            }
        }
        .sheet(isPresented: $isAssigningSpeakers) {
            if let transcript = recording.transcript {
                SpeakerAssignmentSheet(recording: recording, transcript: transcript)
            }
        }
        .task(id: recording.id) {
            hasAudio = appModel.library.audioURL(for: recording) != nil
            appModel.loadPlayer(for: recording)
        }
        .task(id: transcript?.modifiedAt) {
            layout = recording.transcript.map(TranscriptLayout.init) ?? .empty
        }
        // Reset scroll position and local state when the selection changes.
        .id(recording.id)
    }

    private func play(_ segment: TranscriptSegment) {
        appModel.player.seek(to: segment.start)
        if !appModel.player.isPlaying { appModel.player.play() }
    }
}

#if DEBUG
#Preview(traits: .sampleLibrary) {
    @Previewable @Environment(AppModel.self) var appModel
    RecordingDetailView(recording: SampleData.firstMeeting(in: appModel.library.modelContext))
        .frame(width: 760, height: 700)
}
#endif
