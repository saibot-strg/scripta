import SwiftUI

/// Player and map of the conversation in one, pinned above the transcript and
/// aligned with it: who speaks when, one thin lane per voice. A click or a
/// drag on the lanes moves the playback position.
struct PlaybackTimelineView: View {
    @Environment(AppModel.self) private var appModel
    let lanes: [SpeakerLane]
    /// End of the last passage, the timeline's length while no audio is loaded.
    let transcriptEnd: TimeInterval

    /// Height of the bars; each lane's row is as tall as its name.
    private static let barHeight: CGFloat = 6
    private static let rowHeight: CGFloat = 14
    private static let rowSpacing: CGFloat = 4
    /// More voices than this share one lane and are told apart by color only.
    private static let maximumLanes = 5

    var body: some View {
        let player = appModel.player
        let extent = max(player.duration, transcriptEnd, 0.1)
        let isStacked = lanes.count > 1 && lanes.count <= Self.maximumLanes

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlayPauseButton(player: player)
                HStack(spacing: 8) {
                    Button("15 Sekunden zurück", systemImage: "gobackward.15", action: skipBack)
                    Button("15 Sekunden vor", systemImage: "goforward.15", action: skipForward)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                TimelineClock(player: player)
                Spacer(minLength: 8)
                PlaybackRateMenu(player: player)
            }

            HStack(alignment: .top, spacing: 12) {
                if isStacked {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(lanes) { lane in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(lane.tint)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: lane.speaker?.displayName ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(height: Self.rowHeight)
                        }
                    }
                    .frame(maxWidth: 120, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
                }

                tracks(extent: extent, isStacked: isStacked)
                    .overlay {
                        if lanes.count > 1 {
                            TimelinePlayhead(player: player, extent: extent)
                        } else {
                            TimelineProgress(player: player, extent: extent, barHeight: Self.barHeight)
                        }
                    }
                    .overlay {
                        TimelineScrubber(player: player, extent: extent)
                    }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(.background)
        .disabled(!player.isAvailable)
        .help(player.isAvailable ? Text(verbatim: "") : Text("Für diese Aufnahme gibt es keine Audiodatei."))
    }

    /// One row per voice; a single quiet track for one voice (where it speaks
    /// in grey, the progress drawn over it); one shared track for many voices.
    @ViewBuilder
    private func tracks(extent: TimeInterval, isStacked: Bool) -> some View {
        if isStacked {
            VStack(spacing: Self.rowSpacing) {
                ForEach(lanes) { lane in
                    track {
                        SpanShape(spans: lane.spans, duration: extent)
                            .fill(lane.tint)
                    }
                }
            }
        } else if lanes.count > 1 {
            track {
                ForEach(lanes) { lane in
                    SpanShape(spans: lane.spans, duration: extent)
                        .fill(lane.tint)
                }
            }
        } else {
            track {
                ForEach(lanes) { lane in
                    SpanShape(spans: lane.spans, duration: extent)
                        .fill(Color.primary.opacity(0.14))
                }
            }
        }
    }

    private func track(@ViewBuilder bars: () -> some View) -> some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(0.06))
            bars()
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
    }

    private func skipBack() {
        appModel.player.skip(by: -PlayerModel.skipInterval)
    }

    private func skipForward() {
        appModel.player.skip(by: PlayerModel.skipInterval)
    }
}

/// The turns of one voice as fine bars along the time axis.
struct SpanShape: Shape {
    let spans: [ClosedRange<TimeInterval>]
    let duration: TimeInterval

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard duration > 0, rect.width > 0 else { return path }
        for span in spans {
            let start = rect.minX + rect.width * min(max(span.lowerBound / duration, 0), 1)
            let end = rect.minX + rect.width * min(max(span.upperBound / duration, 0), 1)
            // Very short turns stay visible as a fine stroke.
            let width = min(max(end - start, 2), rect.maxX - start)
            guard width > 0 else { continue }
            let radius = min(width, rect.height, 4) / 2
            path.addRoundedRect(
                in: CGRect(x: start, y: rect.minY, width: width, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
        }
        return path
    }
}

/// The one filled control: play or pause.
private struct PlayPauseButton: View {
    let player: PlayerModel

    var body: some View {
        Button(action: player.togglePlayPause) {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("Wiedergabe starten oder pausieren (Leertaste)")
        .accessibilityLabel(Text(player.isPlaying ? "Pause" : "Wiedergabe"))
    }
}

/// Position and length. Only this, the playhead and the progress follow the
/// playback position (20 times per second), not the lanes.
private struct TimelineClock: View {
    let player: PlayerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Formatters.timestamp(player.currentTime))
                .font(.title3.weight(.medium))
            Text("von \(Formatters.timestamp(player.duration))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// A fine line across the lanes of several voices.
private struct TimelinePlayhead: View {
    let player: PlayerModel
    let extent: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary)
                .frame(width: 2)
                .padding(.vertical, -2)
                .offset(x: proxy.size.width * min(max(player.currentTime / extent, 0), 1) - 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// For a single voice: what has been heard, in the accent color, and a knob.
private struct TimelineProgress: View {
    let player: PlayerModel
    let extent: TimeInterval
    let barHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * min(max(player.currentTime / extent, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(x, 0), height: barHeight)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: min(max(x - 6, 0), max(proxy.size.width - 12, 0)))
            }
            .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Click or drag anywhere on the lanes; VoiceOver gets a slider instead.
private struct TimelineScrubber: View {
    @Bindable var player: PlayerModel
    let extent: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard proxy.size.width > 0 else { return }
                            if !player.isScrubbing { player.beginScrubbing() }
                            player.scrub(to: extent * min(max(value.location.x / proxy.size.width, 0), 1))
                        }
                        .onEnded { _ in
                            player.endScrubbing()
                        }
                )
        }
        .accessibilityRepresentation {
            Slider(value: $player.position, in: 0...max(player.duration, 0.1))
                .accessibilityLabel(Text("Position"))
                .accessibilityValue(Text(Formatters.spokenDuration(player.currentTime)))
        }
    }
}
