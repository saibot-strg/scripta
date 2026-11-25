import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import Scripta

@Suite("Live level meters")
struct LiveMeterTests {
    @Test("Gaps on the timeline become silent levels, so every block has one")
    func gapLevels() async throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try AudioFileSink(fileURL: folder.appending(path: "system.caf"), usesTimeline: true)
        let origin = mach_absolute_time()
        sink.startTimeline(at: origin)

        // Nothing plays for 2 s, then 1 s of sound.
        sink.append(
            TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1),
            hostTime: origin + AudioConvertNanosToHostTime(2_000_000_000)
        )
        sink.finish()

        var decibels: [Float] = []
        for await event in sink.events {
            if case .progress(let newDecibels, _) = event { decibels += newDecibels }
        }
        // Host time conversion may round by a frame.
        #expect((59...60).contains(decibels.count), "\(decibels.count) blocks")
        #expect(decibels.prefix(39).allSatisfy { $0 == LevelAccumulator.silenceDecibels })
        #expect(decibels.suffix(19).allSatisfy { $0 > -12 })
    }

    @Test("Level history keeps block numbers when old levels are dropped")
    func history() {
        var history = LevelHistory()
        history.append(contentsOf: (0..<700).map(Float.init))

        #expect(history.count == 700)
        #expect(history.levels.count == LevelHistory.capacity)
        #expect(history.level(at: 699) == 699)
        #expect(history.level(at: 100) == 100)
        #expect(history.level(at: 99) == nil, "dropped")
        #expect(history.level(at: 700) == nil, "not arrived yet")
        #expect(LevelHistory([1, 2, 3]).level(at: 2) == 3)
    }

    @Test("Meter clock trails real time by its delay and stands still while paused")
    func clock() throws {
        let start = ContinuousClock.now
        var clock = MeterClock()
        #expect(clock.position(at: start) == nil)

        clock.start(at: start)
        let delay = MeterClock.initialDelay
        #expect(abs(try #require(clock.position(at: start + .seconds(1))) - (1 - delay) * 20) < 1e-6)

        clock.pause(at: start + .seconds(1))
        #expect(!clock.isRunning)
        #expect(abs(try #require(clock.position(at: start + .seconds(5))) - (1 - delay) * 20) < 1e-6)

        clock.resume(at: start + .seconds(5))
        #expect(clock.isRunning)
        #expect(abs(try #require(clock.position(at: start + .seconds(6))) - (2 - delay) * 20) < 1e-6)
    }

    @Test("Meter clock fits its delay to how late the microphone's batches arrive")
    func calibration() {
        let start = ContinuousClock.now
        var clock = MeterClock()
        clock.start(at: start)

        // Two blocks every 100 ms, arriving 70 ms after the newest one ends; one batch is held up.
        var total = 0
        for batch in 1...MeterClock.calibrationBatches {
            total += 2
            let lateness = batch == 3 ? 0.25 : 0.07
            clock.noteArrival(newBlocks: 2, totalBlocks: total, at: start + .seconds(Double(total) / 20 + lateness))
        }
        // Smallest lateness + one batch + margin.
        #expect(abs(clock.delay - (0.07 + 0.1 + MeterClock.delayMargin)) < 1e-6)

        // Later batches don't move it any more.
        clock.noteArrival(newBlocks: 2, totalBlocks: total + 2, at: start + .seconds(5))
        #expect(abs(clock.delay - (0.07 + 0.1 + MeterClock.delayMargin)) < 1e-6)
    }

    @Test("Live gain is what the leveler applies afterwards and holds while only others talk")
    func liveGain() {
        // A quiet headset: speech at -32 dBFS in 3 of 5 blocks, room noise at -60.
        let blocks: [Float] = (0..<400).map { $0 % 5 < 3 ? -32 : -60 }
        var gain = LiveMicrophoneGain()
        #expect(gain.decibels == 0)

        gain.add(blocks)
        #expect(MicrophoneLeveler.gainDecibels(forBlockDecibels: blocks) == 14)
        #expect(gain.decibels == 14)

        gain.add([Float](repeating: -60, count: LiveMicrophoneGain.windowBlocks))
        #expect(gain.decibels == 14)
    }

    @Test("A loud enough microphone isn't raised")
    func noGainForLoudMicrophone() {
        var gain = LiveMicrophoneGain()
        gain.add((0..<400).map { $0 % 5 < 3 ? -17 : -55 })
        #expect(gain.decibels == 0)
    }
}

@Suite("Level meter drawing")
@MainActor
struct LevelBarsTests {
    private let bounds = CGRect(x: 0, y: 0, width: 50, height: 20)

    private func bars(_ part: LevelBars.Part, _ history: LevelHistory, at position: Double) -> CGRect {
        LevelBars(part: part, history: history, position: position, barWidth: 3, spacing: 2, displayScale: 2)
            .path(in: bounds).boundingRect
    }

    @Test("The newest bar ends at the right edge; a fractional position shifts all bars smoothly")
    func scrolling() {
        let history = LevelHistory([1, 1, 1])
        // Three full-height bars at 37–40, 42–45 and 47–50.
        #expect(bars(.recorded, history, at: 3) == CGRect(x: 37, y: 0, width: 13, height: 20))
        // Half a block later all bars moved 2.5 pt left; the next block slides in at the edge.
        let moved = bars(.recorded, history, at: 3.5)
        #expect(moved.minX == 34.5)
        #expect(moved.maxX == 50)
        // Placeholders only before the first block.
        #expect(bars(.beforeStart, history, at: 3).maxX == 35)
    }
}

@Suite("Remembered microphone gain")
struct MicrophoneGainMemoryTests {
    @Test("The gain is remembered per microphone")
    func perDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: "MicrophoneGainMemoryTests-\(UUID().uuidString)"))
        #expect(MicrophoneGainMemory.gain(forDevice: "headset", defaults: defaults) == nil)
        MicrophoneGainMemory.remember(14, forDevice: "headset", defaults: defaults)
        MicrophoneGainMemory.remember(0, forDevice: "built-in", defaults: defaults)
        #expect(MicrophoneGainMemory.gain(forDevice: "headset", defaults: defaults) == 14)
        #expect(MicrophoneGainMemory.gain(forDevice: "built-in", defaults: defaults) == 0)
        #expect(MicrophoneGainMemory.gain(forDevice: nil, defaults: defaults) == nil)
    }

    @Test("A live gain starts with the remembered value until it has heard enough speech")
    func startsRemembered() {
        var gain = LiveMicrophoneGain(decibels: 14)
        gain.add([Float](repeating: -60, count: 40))
        #expect(gain.decibels == 14)
        #expect(!gain.hasMeasured)
        gain.add((0..<400).map { $0 % 5 < 3 ? -26 : -60 })
        #expect(gain.decibels == 8)
        #expect(gain.hasMeasured)
    }
}

@Suite("Meter gain of the dictation pill")
struct DictationMeterGainTests {
    @Test("Starts with the gain remembered for the microphone")
    func startsWithRememberedGain() {
        #expect(DictationMeterGain(remembered: 14).decibels == 14)
        #expect(DictationMeterGain().decibels == 0)
    }

    @Test("A quiet headset is raised after a fifth of a second of voice, without any pause")
    func followsQuietVoiceQuickly() {
        var gain = DictationMeterGain()
        gain.add([-33, -34, -33])
        #expect(gain.decibels == 0)
        #expect(!gain.hasMeasured)
        gain.add([-33])
        // Speech at -33 dBFS reaches the leveler's target of -18.
        #expect(gain.decibels == 15)
        #expect(gain.hasMeasured)
        #expect(!gain.isReliable)
        gain.add([Float](repeating: -33, count: 6))
        #expect(gain.isReliable)
    }

    @Test("Room noise doesn't count as voice")
    func ignoresRoomNoise() {
        var gain = DictationMeterGain(remembered: 6)
        gain.add([Float](repeating: -58, count: 100))
        #expect(gain.decibels == 6)
        #expect(!gain.hasMeasured)
    }

    @Test("A loud microphone isn't turned down, a faint one isn't raised without limit")
    func staysWithinBounds() {
        var loud = DictationMeterGain(remembered: 10)
        loud.add([Float](repeating: -12, count: 10))
        #expect(loud.decibels == 0)

        var faint = DictationMeterGain()
        faint.add([Float](repeating: -44, count: 10))
        #expect(faint.decibels == MicrophoneLeveler.maximumGainDecibels)
    }

    @Test("With the gain, normal speech moves the bars through most of their travel")
    func speechUsesTheBars() {
        // Levelled speech: loud syllables around -18 dBFS, soft ones around -30.
        let loud = LevelHistory([Float](repeating: LevelMeter.normalizedLevel(decibels: -18), count: 40))
        let soft = LevelHistory([Float](repeating: LevelMeter.normalizedLevel(decibels: -30), count: 40))
        #expect(LogoLevelBars.levels(in: loud, at: 40).allSatisfy { $0 > 0.85 })
        #expect(LogoLevelBars.levels(in: soft, at: 40).allSatisfy { $0 > 0.25 && $0 < 0.45 })
    }
}

@Suite("Logo bars in the dictation pill")
struct LogoLevelBarsTests {
    private func levels(_ value: Float, count: Int = 40) -> LevelHistory {
        LevelHistory([Float](repeating: value, count: count))
    }

    @Test("Silence and room noise leave the logo small, speech raises it to full size")
    func restAndSpeech() {
        #expect(LogoLevelBars.levels(in: levels(0), at: 40).allSatisfy { $0 == 0 })
        #expect(LogoLevelBars.levels(in: levels(0.25), at: 40).allSatisfy { $0 == 0 })
        #expect(LogoLevelBars.levels(in: levels(0.9), at: 40).allSatisfy { $0 == 1 })
    }

    @Test("The tall bar reacts first, the others follow")
    func tallBarFirst() {
        // Silence, then speech starting at block 38.
        let history = LevelHistory([Float](repeating: 0, count: 38) + [0.9, 0.9])
        let bars = LogoLevelBars.levels(in: history, at: 39.2)
        #expect(bars[1] > 0)
        #expect(bars[3] == 0)
    }

    @Test("At rest the bars keep the logo's proportions")
    func proportions() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 16)
        let path = LogoBarsShape(levels: [1, 1, 1, 1]).path(in: rect)
        #expect(path.boundingRect.height == 16)
        #expect(abs(path.boundingRect.width - 24) < 0.01)
    }
}
