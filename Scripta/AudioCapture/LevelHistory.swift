/// The recent meter levels of one track, each tied to its 50 ms block on the
/// recording's timeline, so meters can place them by time instead of by
/// arrival.
struct LevelHistory: Equatable {
    /// 30 s, more than the widest meter shows.
    static let capacity = 600

    /// Levels 0...1, oldest first.
    private(set) var levels: [Float] = []
    /// Blocks recorded so far; the newest level belongs to block `count - 1`.
    private(set) var count = 0

    var isEmpty: Bool { count == 0 }

    init() {}

    /// A history whose blocks are just these levels.
    init(_ levels: [Float]) {
        self.levels = Array(levels.suffix(Self.capacity))
        count = levels.count
    }

    mutating func append(contentsOf newLevels: [Float]) {
        guard !newLevels.isEmpty else { return }
        levels.append(contentsOf: newLevels)
        count += newLevels.count
        if levels.count > Self.capacity {
            levels.removeFirst(levels.count - Self.capacity)
        }
    }

    /// The level of block `index`, or nil when it hasn't arrived yet or is too old.
    func level(at index: Int) -> Float? {
        let position = index - (count - levels.count)
        return levels.indices.contains(position) ? levels[position] : nil
    }
}
