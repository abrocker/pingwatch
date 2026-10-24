/// Summary of a run of ping results. A nil entry is a ping that got no answer.
public struct LatencyStats: Equatable {
    public let count: Int
    public let lost: Int
    public let last: Double?
    public let avg: Double?
    public let min: Double?
    public let max: Double?

    public var lossPercent: Double { count == 0 ? 0 : Double(lost) / Double(count) * 100 }

    public init(_ values: [Double?]) {
        var sum = 0.0
        var answered = 0
        var lowest: Double?
        var highest: Double?
        for case let value? in values {
            sum += value
            answered += 1
            if lowest == nil || value < lowest! { lowest = value }
            if highest == nil || value > highest! { highest = value }
        }
        count = values.count
        lost = values.count - answered
        last = values.last.flatMap { $0 }
        avg = answered == 0 ? nil : sum / Double(answered)
        min = lowest
        max = highest
    }
}
