import SwiftUI
import Charts
import PingCore

extension Array where Element == PingSample {
    /// About `limit` samples at most, for drawing. Each stretch of the history keeps its slowest answer
    /// and, if there was one, a lost ping, so spikes and gaps stay visible.
    func reduced(to limit: Int) -> [PingSample] {
        guard count > limit else { return self }
        var result: [PingSample] = []
        result.reserveCapacity(limit * 2)
        for range in Downsample.ranges(count: count, limit: limit) {
            var miss: PingSample?
            var slowest: PingSample?
            for sample in self[range] {
                if let ms = sample.latencyMs {
                    if ms > (slowest?.latencyMs ?? -1) { slowest = sample }
                } else if miss == nil {
                    miss = sample
                }
            }
            if let miss { result.append(miss) }
            if let slowest { result.append(slowest) }
        }
        return result.sorted { $0.date < $1.date }
    }
}

enum LatencyLevel {
    static func color(_ ms: Double) -> Color {
        switch ms {
        case ..<100: return .green
        case ..<200: return .yellow
        default: return .red
        }
    }
}

/// Small history graph for a table row: one bar per ping, height = response time, colour = how slow it was,
/// a full-height red bar where the host did not answer. Drawn on a Canvas, because a Charts view per row is costly.
struct LatencyBars: View {
    let samples: [PingSample]
    let window: Int

    /// The visible time range: the last `window` seconds, or everything from `firstDate` if window is 0.
    static func timeDomain(window: Int, firstDate: Date?) -> ClosedRange<Date> {
        let end = Date()
        let start = window > 0 ? end.addingTimeInterval(-Double(window)) : (firstDate ?? end)
        return (start < end ? start : end.addingTimeInterval(-60))...end
    }

    var body: some View {
        let shown = samples.reduced(to: 90)
        let domain = Self.timeDomain(window: window, firstDate: shown.first?.date)
        let span = max(domain.upperBound.timeIntervalSince(domain.lowerBound), 1)
        let ceiling = max(100, (shown.compactMap(\.latencyMs).max() ?? 0) * 1.15)

        Canvas { context, size in
            for sample in shown {
                let x = CGFloat(sample.date.timeIntervalSince(domain.lowerBound) / span) * size.width
                guard x >= 0 else { continue }
                if let ms = sample.latencyMs {
                    let height = max(2, CGFloat(ms / ceiling) * size.height)
                    context.fill(Path(CGRect(x: x - 1, y: size.height - height, width: 2, height: height)),
                                 with: .color(LatencyLevel.color(ms)))
                } else {
                    context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)),
                                 with: .color(.red.opacity(0.6)))
                }
            }
        }
    }
}
