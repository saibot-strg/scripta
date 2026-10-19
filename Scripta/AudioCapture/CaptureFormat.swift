import AVFoundation

/// Fixed format used while recording.
///
/// Audio is always captured as 16-bit PCM in a CAF file: Core Audio keeps the
/// file header up to date on every write, so the file stays readable up to the
/// last written buffer even if the app crashes. After recording, the file is
/// encoded to AAC unless the user chose lossless storage.
enum CaptureFormat {
    static let sampleRate: Double = 48_000
    static let fileName = "recording.caf"
    /// Meeting tracks.
    static let microphoneFileName = "microphone.caf"
    static let systemFileName = "system.caf"
    static let mixFileName = "mix.caf"

    /// Name of the AAC version of a PCM file ("recording.caf" → "recording.m4a").
    static func encodedFileName(for fileName: String) -> String {
        (fileName as NSString).deletingPathExtension + ".m4a"
    }

    /// Float32 mono buffers handed to the file writer.
    static var processingFormat: AVAudioFormat {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            preconditionFailure("48 kHz mono is always a valid format")
        }
        return format
    }

    /// 16-bit little-endian PCM on disk.
    static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}

/// How finished recordings are stored (setting).
enum RecordingFileFormat: String, CaseIterable, Identifiable, Sendable {
    case aac
    case lossless

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .aac: "AAC (kompakt)"
        case .lossless: "Verlustfrei (CAF)"
        }
    }
}

/// AAC quality (setting).
enum RecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard
    case high

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .standard: "Standard (64 kbit/s)"
        case .high: "Hoch (128 kbit/s)"
        }
    }

    var aacBitRate: Int {
        switch self {
        case .standard: 64_000
        case .high: 128_000
        }
    }
}

/// Converts RMS amplitudes to a 0...1 level for meters.
enum LevelMeter {
    /// Quietest level that still shows (in dBFS).
    static let floorDecibels: Float = -50

    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
