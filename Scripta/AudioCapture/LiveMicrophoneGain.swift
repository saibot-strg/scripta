/// Estimates during a recording the gain `MicrophoneLeveler` applies once it
/// is finished, so the live meter shows a quiet microphone as it will sound
/// and not as a flat line.
struct LiveMicrophoneGain {
    /// The speech level is judged over the last 5 minutes …
    static let windowBlocks = 6_000
    /// … once per second.
    static let updateBlocks = 20

    /// Current gain in dB: the remembered one until there is enough speech.
    private(set) var decibels: Float
    /// Measured from this recording's speech at least once.
    private(set) var hasMeasured = false
    private var recent: [Float] = []
    private var blocksSinceUpdate = 0

    /// - Parameter decibels: Gain to start with, e.g. the one remembered for
    ///   this microphone (see `MicrophoneGainMemory`).
    init(decibels: Float = 0) {
        self.decibels = decibels
    }

    mutating func add(_ blockDecibels: [Float]) {
        recent.append(contentsOf: blockDecibels)
        if recent.count > Self.windowBlocks {
            recent.removeFirst(recent.count - Self.windowBlocks)
        }
        blocksSinceUpdate += blockDecibels.count
        guard blocksSinceUpdate >= Self.updateBlocks else { return }
        blocksSinceUpdate = 0
        // Without enough speech (e.g. only the others talk) the last gain stays.
        if let speech = MicrophoneLeveler.speechDecibels(forBlockDecibels: recent) {
            decibels = MicrophoneLeveler.gainDecibels(forSpeechDecibels: speech) ?? 0
            hasMeasured = true
        }
    }
}
