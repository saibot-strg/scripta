import AVFoundation
import os

/// Plays short excerpts of one speaker; each start plays the next excerpt.
@MainActor
@Observable
final class ExcerptPlayer {
    /// A passage to play, in seconds of the recording.
    struct Excerpt: Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }

    private(set) var playingID: UUID?
    /// Why the last excerpt could not be played, for an alert.
    var failure: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var nextIndex: [UUID: Int] = [:]

    func toggle(_ id: UUID, url: URL?, excerpts: [Excerpt]) {
        let wasPlaying = playingID == id
        stop()
        guard !wasPlaying, !excerpts.isEmpty else { return }
        guard let url else {
            failure = String(localized: "Für diese Aufnahme gibt es keine Audiodatei.")
            return
        }
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            Logger.playback.error("Excerpt could not be loaded: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
            return
        }
        let index = (nextIndex[id] ?? 0) % excerpts.count
        nextIndex[id] = index + 1
        let excerpt = excerpts[index]
        player.currentTime = excerpt.start
        guard player.play() else {
            failure = String(localized: "Die Wiedergabe konnte nicht gestartet werden.")
            return
        }
        self.player = player
        playingID = id
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(excerpt.end - excerpt.start, 1)))
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
