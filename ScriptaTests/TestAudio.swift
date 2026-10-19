import AVFoundation
import Foundation
import SwiftData
@testable import Scripta

/// Helpers for generating audio in tests.
enum TestAudio {
    /// A sine tone buffer in the given format.
    static func tone(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        duration: TimeInterval,
        frequency: Double = 440,
        amplitude: Float = 0.5
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for index in 0..<Int(frames) {
                samples[index] = amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
            }
        }
        return buffer
    }

    /// Feeds `duration` seconds of tone into the sink in 100 ms buffers.
    static func feed(_ sink: AudioFileSink, sampleRate: Double, channels: AVAudioChannelCount, duration: TimeInterval) {
        let chunks = Int((duration / 0.1).rounded())
        for _ in 0..<chunks {
            sink.append(tone(sampleRate: sampleRate, channels: channels, duration: 0.1))
        }
    }

    static func temporaryDirectory() -> URL {
        let url = URL.temporaryDirectory.appending(path: "ScriptaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// On-disk SwiftData stores for tests. They live outside the per-test folders
/// (which are deleted while the container may still be open) and are cleaned
/// up on later runs.
enum TestStore {
    private static let folder = URL.temporaryDirectory.appending(path: "ScriptaTestStores", directoryHint: .isDirectory)

    static func makeContainer() throws -> ModelContainer {
        removeStaleStores()
        let directory = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try ModelContainerFactory.makeOnDisk(at: directory.appending(path: "Library.store"))
    }

    private static func removeStaleStores() {
        let cutoff = Date.now.addingTimeInterval(-600)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: entry) }
        }
    }
}
