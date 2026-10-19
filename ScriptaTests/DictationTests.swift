import AppKit
import AVFoundation
import Carbon.HIToolbox
import Testing
@testable import Scripta

@Suite("Dictation")
struct DictationTests {
    @Test("Shortcuts display like macOS menus")
    func shortcutDisplay() {
        #expect(KeyShortcut.defaultDictation.displayString.hasPrefix("⌃⌥"))
        #expect(KeyShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0).displayString == "F5")
        let commandShift = KeyShortcut(keyCode: UInt32(kVK_Return), carbonModifiers: UInt32(cmdKey | shiftKey))
        #expect(commandShift.displayString == "⇧⌘↩")
    }

    @Test("Shortcuts survive storage")
    func shortcutStorage() {
        let key = "test.shortcut.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | cmdKey))
        shortcut.save(forKey: key)
        #expect(KeyShortcut.load(forKey: key) == shortcut)
    }

    @Test("Dictation audio is kept as 16 kHz mono in memory")
    func memoryBuffer() {
        let buffer = DictationAudioBuffer()
        for _ in 0..<20 {
            buffer.append(TestAudio.tone(sampleRate: 48_000, channels: 2, duration: 0.1))
        }
        #expect(abs(buffer.duration - 2) < 0.02)
        let samples = buffer.finish()
        #expect(abs(Double(samples.count) - 32_000) < 400)
        #expect(samples.contains { abs($0) > 0.3 })
        // Finished buffers ignore late audio and are empty.
        buffer.append(TestAudio.tone(sampleRate: 48_000, channels: 1, duration: 1))
        #expect(buffer.finish().isEmpty)
    }

    @Test("Text formatting trims and appends a space for the next sentence")
    func formatting() {
        UserDefaults.standard.removeObject(forKey: DictationSettings.appendsSpaceKey)
        #expect(DictationController.format("  Hallo Welt. ") == "Hallo Welt. ")
        #expect(DictationController.format("   ") == "")
    }

    @MainActor
    @Test("The clipboard is restored after pasting and the dictation is marked private")
    func clipboardRestore() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScriptaTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("vorher", forType: .string)
        pasteboard.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom"))

        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("diktiert", forType: .string)
        for marker in TextInserter.privacyMarkers { item.setData(Data(), forType: marker) }
        pasteboard.writeObjects([item])
        #expect(pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)

        snapshot.restore(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "vorher")
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("com.example.custom")) == Data([1, 2, 3]))
    }
}

/// Latency of the recognition step with the real model (opt-in by model availability).
@MainActor
@Suite("Dictation latency", .enabled(if: ParakeetEngine.isModelInstalled))
struct DictationLatencyTests {
    @Test("A 7 s sentence is recognized in well under 300 ms once the model is loaded")
    func recognitionLatency() async throws {
        let url = try #require(Bundle(for: LatencyToken.self).url(forResource: "speech-en", withExtension: "m4a"))
        let file = try AVAudioFile(forReading: url)
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let buffer = DictationAudioBuffer()
        buffer.append(input)
        let samples = buffer.finish()

        let library = LibraryService(modelContext: ModelContainerFactory.makeInMemory().mainContext,
                                     storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory()))
        let service = TranscriptionService(library: library)
        try await service.prepareModel() // includes the warm-up inference

        var timings: [Duration] = []
        var text = ""
        for _ in 0..<3 {
            let start = ContinuousClock.now
            text = try await service.dictate(samples: samples)
            timings.append(start.duration(to: .now))
        }
        let best = timings.min()!
        print("DICTATION LATENCY \(Double(samples.count) / 16_000) s audio → \(timings) – \(text)")
        #expect(text.lowercased().contains("good morning"))
        #expect(best < .milliseconds(300), "recognition took \(best)")
    }
}

private final class LatencyToken {}
