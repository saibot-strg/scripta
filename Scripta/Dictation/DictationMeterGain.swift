/// Raises the dictation pill's meter to a normal speech level within the first
/// syllables, for the display only.
///
/// `LiveMicrophoneGain` is made for recordings: it judges once a second and
/// needs pauses to tell speech from the noise floor. A dictation is a few
/// seconds of speech without pauses, so here everything clearly louder than a
/// quiet room counts as voice.
struct DictationMeterGain {
    /// Blocks (50 ms, dBFS RMS) louder than this count as voice.
    static let voiceDecibels: Float = -45
    /// Voice needed before the gain follows this dictation: 0.2 s.
    static let minimumVoiceBlocks = 4
    /// The level is judged over the last 10 s of voice.
    static let windowBlocks = 200

    /// Current gain in dB: the remembered one until there is enough voice.
    private(set) var decibels: Float
    private var voice: [Float] = []

    /// - Parameter remembered: Gain last measured for this microphone (see
    ///   `MicrophoneGainMemory`), so the first syllable already shows right.
    init(remembered: Float? = nil) {
        decibels = remembered ?? 0
    }

    /// Measured from this dictation's voice at least once.
    var hasMeasured: Bool { voice.count >= Self.minimumVoiceBlocks }

    /// Enough voice (0.5 s, as the leveler asks) to remember the gain for next time.
    var isReliable: Bool { voice.count >= MicrophoneLeveler.minimumSpeechBlocks }

    mutating func add(_ blockDecibels: [Float]) {
        let loud = blockDecibels.filter { $0 > Self.voiceDecibels }
        guard !loud.isEmpty else { return }
        voice.append(contentsOf: loud)
        if voice.count > Self.windowBlocks {
            voice.removeFirst(voice.count - Self.windowBlocks)
        }
        guard hasMeasured else { return }
        // The leveler's measure: the 90th percentile of the speech reaches the target.
        let sorted = voice.sorted()
        let speech = sorted[sorted.count * 9 / 10]
        decibels = min(max(MicrophoneLeveler.targetDecibels - speech, 0), MicrophoneLeveler.maximumGainDecibels)
    }
}
