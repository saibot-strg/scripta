#if DEBUG
import AppKit
import SwiftUI
import SwiftData
import os

/// Launch arguments for UI development (debug builds only):
/// - `-SeedSampleData`: fills an empty library with dummy recordings.
/// - `-SelectRecording <title>`: selects the recording with that title.
/// - `-UISnapshot`: writes PNGs of all windows to the container's tmp folder.
/// - `-RecordTestTone`: starts a recording from a synthetic tone (no microphone),
///   e.g. to test crash recovery with `kill -9`. `-StopRecordingAfter <s>` stops it.
/// - `-RecordTestMeeting`: like `-RecordTestTone`, but a meeting with two tone tracks.
/// - `-ProbeSystemAudio`: builds (but doesn't start) the system audio tap and logs it.
/// - `-AutoPlay <s>`: starts playback after the given delay and logs the player state.
@MainActor
enum DebugLaunchOptions {
    private static let arguments = CommandLine.arguments

    static func apply(to model: AppModel) {
        let context = model.library.modelContext

        if arguments.contains("-SeedSampleData"),
           (try? context.fetchCount(FetchDescriptor<Recording>())) == 0 {
            model.perform { try model.library.insertSampleData() }
        }

        if let title = value(after: "-SelectRecording") {
            let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.title == title })
            model.selectedRecordingID = (try? context.fetch(descriptor).first)?.id
        }

        if arguments.contains("-RecordTestTone") || arguments.contains("-RecordTestMeeting") {
            model.recorder.usesTestTone = true
            Task {
                if arguments.contains("-RecordTestMeeting") {
                    await model.startMeeting(.allSystemAudio)
                } else {
                    await model.startRecording()
                }
                // `-StopRecordingAfter <seconds>` ends the test recording like the stop button.
                if let seconds = value(after: "-StopRecordingAfter").flatMap(Double.init) {
                    try? await Task.sleep(for: .seconds(seconds))
                    model.stopRecording()
                }
            }
        }

        if arguments.contains("-ProbeSystemAudio") {
            Task {
                let url = URL.temporaryDirectory.appending(path: "probe.caf")
                defer { try? FileManager.default.removeItem(at: url) }
                for target in [SystemAudioTarget.allSystemAudio] + AudioAppCatalog.availableApps().prefix(2).map(SystemAudioTarget.application) {
                    do {
                        let sink = try AudioFileSink(fileURL: url)
                        let result = try await SystemAudioCapture(target: target).probe(sink: sink)
                        sink.finish()
                        Logger.recording.notice("Probe \(target.displayName, privacy: .public): \(result, privacy: .public)")
                    } catch {
                        Logger.recording.error("Probe \(target.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        if let delay = value(after: "-AutoPlay").flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                let player = model.player
                Logger.playback.notice("AutoPlay: available=\(player.isAvailable, privacy: .public) url=\(player.loadedURL?.lastPathComponent ?? "nil", privacy: .public)")
                player.play()
                try? await Task.sleep(for: .seconds(1.5))
                Logger.playback.notice("AutoPlay: playing=\(player.isPlaying, privacy: .public) time=\(player.currentTime, format: .fixed(precision: 2))")
            }
        }

        if arguments.contains("-UISnapshot") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                writeContentSnapshots(model: model)
                writeSnapshots()
            }
        }
    }

    /// Renders rows and the selected recording's content with `ImageRenderer`,
    /// in light and dark mode. Window snapshots miss scroll view contents.
    private static func writeContentSnapshots(model: AppModel) {
        let recordings = (try? model.library.modelContext.fetch(
            FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let content = VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 0) {
                ForEach(recordings) { RecordingRow(recording: $0).padding(.horizontal, 12) }
            }
            .frame(width: 340)
            if let recording = model.selectedRecording {
                DetailHeaderView(recording: recording)
                if let transcript = recording.transcript {
                    VStack(alignment: .leading, spacing: 0) {
                        TranscriptView(transcript: transcript, style: .bubbles)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        TranscriptView(transcript: transcript, style: .text)
                    }
                }
                PlayerBarView()
            }
            if model.recorder.isActive {
                RecordingCapsuleView().frame(width: 360)
            }
        }
        .padding(28)
        .frame(width: 760)
        .environment(model)

        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: content
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color.black : Color.white))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL.temporaryDirectory.appending(path: "ui-content-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Renders each visible window's view hierarchy (no screen recording permission needed).
    private static func writeSnapshots() {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let layer = view.layer,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                  let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            // Layer rendering also captures layer-hosted content (lists, SwiftUI text),
            // which `cacheDisplay` skips. Glass and vibrancy still render flat.
            let scale = bitmap.size.width > 0 ? CGFloat(bitmap.pixelsWide) / bitmap.size.width : 1
            graphics.cgContext.scaleBy(x: scale, y: scale)
            layer.render(in: graphics.cgContext)
            let url = URL.temporaryDirectory.appending(path: "ui-snapshot-\(index).png")
            do {
                try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                Logger.app.debug("UI snapshot written to \(url.path(percentEncoded: false), privacy: .public)")
            } catch {
                Logger.app.error("UI snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
