public enum HopDelta {
    /// How much latency each hop adds compared with the closest earlier hop that answered.
    /// The first answering hop's delta is its own latency. Hops without data stay nil.
    public static func compute(averages: [Double?]) -> [Double?] {
        var previous: Double?
        return averages.map { average in
            guard let average else { return nil }
            defer { previous = average }
            return average - (previous ?? 0)
        }
    }
}
