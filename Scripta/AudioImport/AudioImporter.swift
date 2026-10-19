import AVFoundation
import Foundation
import UniformTypeIdentifiers
import os

/// Brings external audio and video files into the library.
///
/// Audio files are copied unchanged (on APFS usually as an instant clone);
/// the user's original stays where it is, untouched. Videos and containers
/// Core Audio can't read keep only their audio track, exported as AAC.
/// Converting to 16 kHz mono happens later, streamed during transcription.
enum AudioImporter {
    /// File types offered in the open panel and accepted by drag & drop.
    static let supportedTypes: [UTType] = [.audio, .movie, .audiovisualContent]

    struct Prepared: Sendable {
        let manifest: RecordingManifest
        let duration: TimeInterval
    }

    /// Copies or extracts the audio into a new recording folder and writes its
    /// manifest. Runs off the main actor. The caller adds it to the library.
    static func prepare(_ source: URL, storage: RecordingStorage) async throws(ImportError) -> Prepared {
        let displayName = source.lastPathComponent
        let isScoped = source.startAccessingSecurityScopedResource()
        defer { if isScoped { source.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        do {
            try storage.makeFolder(for: id)
            let fileName: String
            if await !hasVideo(source), isReadableAudioFile(source) {
                let ext = source.pathExtension.lowercased()
                fileName = "original." + (ext.isEmpty ? "audio" : ext)
                try copy(source, to: storage.fileURL(for: id, fileName: fileName))
            } else {
                fileName = "audio.m4a"
                try await exportAudioTrack(of: source, to: storage.fileURL(for: id, fileName: fileName), displayName: displayName)
            }

            guard let duration = AudioFileInfo.duration(of: storage.fileURL(for: id, fileName: fileName)), duration > 0 else {
                throw ImportError.noAudio(fileName: displayName)
            }
            let manifest = RecordingManifest(
                id: id,
                title: source.deletingPathExtension().lastPathComponent,
                createdAt: .now,
                source: .importedFile,
                fileName: fileName
            )
            // Until it is in the library, an interrupted import is recovered like a recording.
            try storage.writeManifest(manifest)
            Logger.storage.info("Imported \(displayName, privacy: .private) as \(fileName, privacy: .public)")
            return Prepared(manifest: manifest, duration: duration)
        } catch {
            try? storage.removeFolder(for: id)
            if let importError = error as? ImportError { throw importError }
            throw .copyFailed(fileName: displayName, underlying: error)
        }
    }

    /// Videos are never copied: Core Audio can read the sound of some movies
    /// directly, but the library only keeps audio.
    private static func hasVideo(_ url: URL) async -> Bool {
        let tracks = (try? await AVURLAsset(url: url).loadTracks(withMediaType: .video)) ?? []
        return !tracks.isEmpty
    }

    /// True for files Core Audio reads directly (mp3, m4a, wav, aac, flac, caf, aiff …).
    static func isReadableAudioFile(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        // Copy under a temporary name, so a partial copy never looks complete.
        let partial = destination.deletingLastPathComponent().appending(path: "importing-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: source, to: partial)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Keeps only the audio track (e.g. of a screen recording or video call).
    private static func exportAudioTrack(of source: URL, to destination: URL, displayName: String) async throws {
        let asset = AVURLAsset(url: source)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else {
            let isPlayable = (try? await asset.load(.isPlayable)) ?? false
            throw isPlayable ? ImportError.noAudio(fileName: displayName) : ImportError.unsupportedFormat(fileName: displayName)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.unsupportedFormat(fileName: displayName)
        }
        try await session.export(to: destination, as: .m4a)
    }
}

enum ImportError: LocalizedError {
    case unsupportedFormat(fileName: String)
    case noAudio(fileName: String)
    case copyFailed(fileName: String, underlying: any Error)

    var fileName: String {
        switch self {
        case .unsupportedFormat(let name), .noAudio(let name), .copyFailed(let name, _): name
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name):
            String(localized: "„\(name)“: Dieses Format wird nicht unterstützt.")
        case .noAudio(let name):
            String(localized: "„\(name)“ enthält keine Tonspur.")
        case .copyFailed(let name, let error):
            String(localized: "„\(name)“ konnte nicht importiert werden: \(error.localizedDescription)")
        }
    }
}
