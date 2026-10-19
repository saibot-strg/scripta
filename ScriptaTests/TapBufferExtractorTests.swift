import AVFoundation
import Testing
@testable import Scripta

@Suite("System audio buffer extraction")
struct TapBufferExtractorTests {
    /// Builds an AudioBufferList with one mono buffer per entry, filled with the given value.
    private func makeList(values: [Float], frames: Int) -> (UnsafeMutableAudioBufferListPointer, [UnsafeMutablePointer<Float>]) {
        let list = AudioBufferList.allocate(maximumBuffers: values.count)
        var storage: [UnsafeMutablePointer<Float>] = []
        for (index, value) in values.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            data.initialize(repeating: value, count: frames)
            storage.append(data)
            list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * MemoryLayout<Float>.size), mData: data)
        }
        return (list, storage)
    }

    private let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!

    @Test("Exactly the tap's buffers: used as they are")
    func exactMatch() throws {
        let (list, storage) = makeList(values: [0.25, -0.25], frames: 512)
        defer { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }

        let buffer = try #require(TapBufferExtractor(format: tapFormat).buffer(from: list.unsafePointer))
        #expect(buffer.frameLength == 512)
        #expect(buffer.floatChannelData![0][0] == 0.25)
        #expect(buffer.floatChannelData![1][0] == -0.25)
    }

    @Test("Headset microphone in front of the tap (USB headset as output): tap channels are picked")
    func headsetInFront() throws {
        // One extra input stream from the headset microphone, then the two tap channels.
        let (list, storage) = makeList(values: [0.9, 0.25, -0.25], frames: 480)
        defer { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }

        let buffer = try #require(TapBufferExtractor(format: tapFormat).buffer(from: list.unsafePointer))
        #expect(buffer.frameLength == 480)
        #expect(buffer.floatChannelData![0][0] == 0.25)
        #expect(buffer.floatChannelData![1][0] == -0.25)
    }

    @Test("Too few buffers are rejected instead of crashing")
    func tooFew() {
        let (list, storage) = makeList(values: [0.5], frames: 256)
        defer { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
        #expect(TapBufferExtractor(format: tapFormat).buffer(from: list.unsafePointer) == nil)
    }
}
