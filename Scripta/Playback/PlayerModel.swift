import AVFoundation
import os

/// Playback of one recording at a time: play/pause, seeking, ±15 s and speed.
///
/// The current time is published every 50 ms while playing, which also drives
/// the transcript highlight (milestone 3).
@MainActor
@Observable
final class PlayerModel {
    nonisolated static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    nonisolated static let skipInterval: TimeInterval = 15

    private(set) var loadedURL: URL?
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    /// Playback position; while scrubbing, the position under the slider.
    private(set) var currentTime: TimeInterval = 0
    private(set) var isScrubbing = false

    var rate: Float = PlaybackSettings.rate {
        didSet {
            player?.rate = rate
            PlaybackSettings.rate = rate
        }
    }

    var isAvailable: Bool { player != nil }

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    /// Loads a file for playback (nil or a missing file unloads).
    func load(_ url: URL?) {
        guard url != loadedURL else { return }
        unload()
        guard let url else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true // must be set before prepareToPlay
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            loadedURL = url
            Logger.playback.info("Loaded \(url.lastPathComponent, privacy: .public) (\(player.duration, format: .fixed(precision: 1)) s)")
        } catch {
            Logger.playback.error("Could not load audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unload() {
        stopTicker()
        player?.stop()
        player = nil
        loadedURL = nil
        isPlaying = false
        isScrubbing = false
        duration = 0
        currentTime = 0
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        // Start over when the end was reached.
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
        }
        let started = player.play()
        if !started { Logger.playback.error("Playback did not start") }
        isPlaying = started
        if started { startTicker() }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        if let player { currentTime = player.currentTime }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let target = min(max(time, 0), duration)
        player.currentTime = target
        currentTime = target
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    // MARK: Scrubbing

    func beginScrubbing() {
        isScrubbing = true
    }

    /// Moves the displayed position without seeking (while dragging).
    func scrub(to time: TimeInterval) {
        currentTime = min(max(time, 0), duration)
    }

    func endScrubbing() {
        isScrubbing = false
        seek(to: currentTime)
    }

    // MARK: Ticker

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                if !self.isScrubbing {
                    self.currentTime = player.currentTime
                }
                if !player.isPlaying {
                    // Reached the end.
                    self.isPlaying = false
                    self.currentTime = player.currentTime
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
