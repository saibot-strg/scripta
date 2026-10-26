import Foundation

/// Segment start times for fast lookup of the segment at a playback position.
struct TranscriptTimeline: Equatable {
    private var starts: [TimeInterval] = []
    private var ids: [UUID] = []

    static let empty = TranscriptTimeline()

    init() {}

    /// `segments` in playback order.
    init(_ segments: [TranscriptSegment]) {
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
