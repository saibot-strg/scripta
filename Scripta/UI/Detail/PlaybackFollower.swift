import SwiftUI

/// Follows the player position and reports the active segment. Kept in its
/// own tiny view so the 20 Hz time updates don't re-render the transcript;
/// the binding only changes when another segment becomes active.
struct PlaybackFollower: View {
    @Environment(AppModel.self) private var appModel
    let timeline: TranscriptTimeline
    @Binding var activeSegmentID: UUID?

    var body: some View {
        let player = appModel.player
        let id = player.isAvailable && (player.isPlaying || player.currentTime > 0)
            ? timeline.segmentID(at: player.currentTime + 0.05)
            : nil
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: id, initial: true) { _, newID in
                activeSegmentID = newID
            }
    }
}
