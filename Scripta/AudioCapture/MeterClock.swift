/// Maps the time of day to a position on the recording's timeline, counted in
/// 50 ms meter blocks, so the meters scroll steadily instead of jumping
/// whenever a batch of levels arrives. Pauses don't count, like on the
/// timeline of the files.
///
/// The meters trail real time by `delay`, so a block has arrived by the time
/// it slides in at the right edge. The microphone delivers 100 ms buffers
/// (two blocks at once), placed up to one buffer early on the timeline; the
/// delay is fitted to that from the first batches.
struct MeterClock: Equatable {
    static let blocksPerSecond: Double = 20
    /// Before the first levels arrive.
    static let initialDelay: Double = 0.15
    static let delayRange: ClosedRange<Double> = 0.08...0.4
    /// Headroom for a busy main thread.
    static let delayMargin: Double = 0.02
    /// Batches of microphone levels that fit the delay.
    static let calibrationBatches = 5

    private var origin: ContinuousClock.Instant?
    private var pausedAt: ContinuousClock.Instant?
    /// Seconds the meters trail real time.
    private(set) var delay = initialDelay
    private var batchesSeen = 0
    private var smallestLateness = Double.infinity
    private var largestBatch = 0

    var isStarted: Bool { origin != nil }

    /// Started and not paused: the meters move.
    var isRunning: Bool { origin != nil && pausedAt == nil }

    /// Still fitting the delay (see `noteArrival`).
    var isCalibrating: Bool { batchesSeen < Self.calibrationBatches }

    mutating func start(at now: ContinuousClock.Instant) {
        self = MeterClock()
        origin = now
    }

    mutating func pause(at now: ContinuousClock.Instant) {
        guard isRunning else { return }
        pausedAt = now
    }

    /// Shifts the origin by the pause, as the file sinks do.
    mutating func resume(at now: ContinuousClock.Instant) {
        guard let origin, let pausedAt else { return }
        self.origin = origin + pausedAt.duration(to: now)
        self.pausedAt = nil
    }

    /// Recorded time in seconds (pauses excluded), or nil before the start.
    func elapsed(at now: ContinuousClock.Instant) -> Double? {
        guard let origin else { return nil }
        return origin.duration(to: pausedAt ?? now).seconds
    }

    /// Where the meters are at `now`: block `i` sits fully at the right edge
    /// once the position reaches `i + 1`. Nil before the start.
    func position(at now: ContinuousClock.Instant) -> Double? {
        elapsed(at: now).map { ($0 - delay) * Self.blocksPerSecond }
    }

    /// Fits the delay to how late the microphone's levels arrive: `newBlocks`
    /// just arrived at `now`, `totalBlocks` are known in all.
    mutating func noteArrival(newBlocks: Int, totalBlocks: Int, at now: ContinuousClock.Instant) {
        guard isCalibrating, newBlocks > 0, isRunning,
              let elapsed = elapsed(at: now) else { return }
        batchesSeen += 1
        // How far the newest block lags real time; hiccups only add to it.
        smallestLateness = min(smallestLateness, elapsed - Double(totalBlocks) / Self.blocksPerSecond)
        largestBatch = max(largestBatch, newBlocks)
        guard batchesSeen == Self.calibrationBatches else { return }
        // The next block arrives one batch after the newest one.
        let fitted = smallestLateness + Double(largestBatch) / Self.blocksPerSecond + Self.delayMargin
        delay = min(max(fitted, Self.delayRange.lowerBound), Self.delayRange.upperBound)
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
