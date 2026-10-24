public enum Downsample {
    /// Splits `count` items into at most `limit` consecutive index ranges of nearly equal size,
    /// so a long history can be drawn with a bounded number of marks.
    public static func ranges(count: Int, limit: Int) -> [Range<Int>] {
        guard count > 0, limit > 0 else { return [] }
        guard count > limit else { return (0..<count).map { $0..<($0 + 1) } }
        let size = (count + limit - 1) / limit
        return stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
    }
}
