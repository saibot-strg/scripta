import SwiftUI

/// Segment start times for fast lookup of the segment at a playback position.
struct TranscriptTimeline: Equatable {
    private var starts: [TimeInterval] = []
    private var ids: [UUID] = []

    static let empty = TranscriptTimeline()

    init() {}

    init(_ transcript: Transcript?) {
        let segments = transcript?.orderedSegments ?? []
        starts = segments.map(\.start)
        ids = segments.map(\.id)
    }

    /// The last segment that started at or before `time` (binary search).
    func segmentID(at time: TimeInterval) -> UUID? {
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? ids[low - 1] : nil
    }
}

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
