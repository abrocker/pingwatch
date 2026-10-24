import SwiftUI
import Charts
import PingCore

/// Trace Graph in the style of PingPlotter: a table with one row per router on the left and,
/// aligned with the rows, a latency graph on the right. Each row shows the range of response
/// times (grey bar), the packet loss (red bar from the left), the average (circle) and the latest
/// answer (blue dot). The averages are joined by a line, so a jump to the right shows which
/// hop adds latency. The last row is the round trip to the target itself.
struct TraceGraph: View {
    @EnvironmentObject var monitor: Monitor
    let hostID: UUID
    /// The hop whose timeline is shown below; nil means the target (round trip).
    @Binding var selectedHop: Int?
    var roundTripLabel = "Round Trip (ms)"

    private static let rowHeight: CGFloat = 26
    private static let headerHeight: CGFloat = 24
    private static let tableWidth: CGFloat = 540

    var body: some View {
        let hops = monitor.hops(for: hostID)
        let roundTrip = monitor.stats(for: hostID)
        let selectedIndex = selectedHop.flatMap { hop in hops.firstIndex { $0.hop == hop } } ?? hops.count
        let slowest = (hops.map(\.stats.max) + [roundTrip.max]).compactMap { $0 }.max() ?? 0
        let xMax = max(200, (slowest * 1.1 / 50).rounded(.up) * 50)

        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        columnHeader
                        ForEach(hops) { hop in
                            row(label: "\(hop.hop)", address: hop.address,
                                name: hop.address.flatMap { monitor.hostNames[$0] } ?? "",
                                stats: hop.stats, selected: selectedIndex == hops.firstIndex { $0.hop == hop.hop })
                                .onTapGesture { selectedHop = hop.hop }
                        }
                        roundTripRow(roundTrip, selected: selectedIndex == hops.count)
                            .onTapGesture { selectedHop = nil }
                    }
                    .frame(width: Self.tableWidth)

                    VStack(spacing: 0) {
                        graphHeader(xMax: xMax)
                        graph(hops: hops, roundTrip: roundTrip, selectedIndex: selectedIndex, xMax: xMax)
                    }
                    .frame(minWidth: 240, maxWidth: .infinity)
                }
            }
            if hops.isEmpty {
                Text("Route wird ermittelt …").font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
            }
        }
    }

    // MARK: - Table

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Hop").frame(width: 44, alignment: .leading)
            Text("Pings").frame(width: 44, alignment: .trailing)
            Text("IP").frame(width: 118, alignment: .leading).padding(.leading, 8)
            Text("Name").frame(width: 130, alignment: .leading)
            Text("Ø").frame(width: 50, alignment: .trailing)
            Text("Min").frame(width: 50, alignment: .trailing)
            Text("Akt.").frame(width: 50, alignment: .trailing)
            Text("Verl.%").frame(width: 54, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(height: Self.headerHeight)
    }

    private func row(label: String, address: String?, name: String, stats: LatencyStats,
                     selected: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(stats.avg.map(LatencyLevel.color) ?? .gray).frame(width: 10, height: 10)
                Text(label).monospacedDigit()
            }
            .frame(width: 44, alignment: .leading)
            Text("\(stats.count)").monospacedDigit().frame(width: 44, alignment: .trailing)
            Text(address ?? "–")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(address == nil ? .secondary : .primary)
                .frame(width: 118, alignment: .leading)
                .padding(.leading, 8)
            Text(name).lineLimit(1).truncationMode(.middle).frame(width: 130, alignment: .leading)
            numbers(stats)
        }
        .font(.system(size: 12))
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    private func roundTripRow(_ stats: LatencyStats, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(stats.count)").monospacedDigit().frame(width: 88, alignment: .trailing)
            Text(roundTripLabel).fontWeight(.semibold).frame(width: 248, alignment: .trailing)
            numbers(stats)
        }
        .font(.system(size: 12))
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func numbers(_ stats: LatencyStats) -> some View {
        Text(number(stats.avg)).monospacedDigit().frame(width: 50, alignment: .trailing)
        Text(number(stats.min)).monospacedDigit().frame(width: 50, alignment: .trailing)
        if stats.count > 0, stats.last == nil {
            Text("ERR").foregroundStyle(.red).frame(width: 50, alignment: .trailing)
        } else {
            Text(number(stats.last)).monospacedDigit().frame(width: 50, alignment: .trailing)
        }
        Text(String(format: "%.1f", stats.lossPercent))
            .monospacedDigit()
            .foregroundStyle(stats.lost > 0 ? .red : .primary)
            .frame(width: 54, alignment: .trailing)
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "–"
    }

    // MARK: - Latency graph

    private func graphHeader(xMax: Double) -> some View {
        HStack {
            Text("0 ms")
            Spacer()
            Text("Latenz")
            Spacer()
            Text("\(Int(xMax)) ms")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: Self.headerHeight)
    }

    private func graph(hops: [HopInfo], roundTrip: LatencyStats, selectedIndex: Int, xMax: Double) -> some View {
        let rowHeight = Self.rowHeight
        let stats = hops.map(\.stats) + [roundTrip]
        let deltas = hops.map(\.delta)
        let hopCount = hops.count

        return Canvas { context, size in
            func x(_ ms: Double) -> CGFloat { CGFloat(min(max(ms, 0), xMax) / xMax) * size.width }
            func y(_ row: Int) -> CGFloat { (CGFloat(row) + 0.5) * rowHeight }

            // Colour zones, like PingPlotter's legend: green, yellow, red.
            context.fill(Path(CGRect(x: 0, y: 0, width: x(100), height: size.height)),
                         with: .color(.green.opacity(0.16)))
            context.fill(Path(CGRect(x: x(100), y: 0, width: x(200) - x(100), height: size.height)),
                         with: .color(.yellow.opacity(0.2)))
            context.fill(Path(CGRect(x: x(200), y: 0, width: size.width - x(200), height: size.height)),
                         with: .color(.red.opacity(0.16)))

            context.fill(Path(CGRect(x: 0, y: CGFloat(selectedIndex) * rowHeight, width: size.width, height: rowHeight)),
                         with: .color(.accentColor.opacity(0.18)))

            for (row, rowStats) in stats.enumerated() {
                let centerY = y(row)

                var separator = Path()
                separator.move(to: CGPoint(x: 0, y: CGFloat(row + 1) * rowHeight))
                separator.addLine(to: CGPoint(x: size.width, y: CGFloat(row + 1) * rowHeight))
                context.stroke(separator, with: .color(.primary.opacity(0.07)), lineWidth: 1)

                if rowStats.lossPercent > 0 {
                    let width = CGFloat(rowStats.lossPercent / 100) * size.width
                    context.fill(Path(CGRect(x: 0, y: centerY - 8, width: width, height: 16)),
                                 with: .color(.red.opacity(0.45)))
                }
                if let low = rowStats.min, let high = rowStats.max {
                    context.fill(Path(roundedRect: CGRect(x: x(low), y: centerY - 3, width: max(2, x(high) - x(low)), height: 6),
                                      cornerRadius: 3),
                                 with: .color(.gray.opacity(0.55)))
                    var whisker = Path()
                    whisker.move(to: CGPoint(x: x(low), y: centerY))
                    whisker.addLine(to: CGPoint(x: x(high), y: centerY))
                    whisker.move(to: CGPoint(x: x(high), y: centerY - 4))
                    whisker.addLine(to: CGPoint(x: x(high), y: centerY + 4))
                    context.stroke(whisker, with: .color(.gray), lineWidth: 1)
                }
            }

            // The line through the averages of the hops: a step to the right is latency added by that hop.
            var line = Path()
            var previous: CGPoint?
            for row in 0..<hopCount {
                guard let average = stats[row].avg else { continue }
                let point = CGPoint(x: x(average), y: y(row))
                if let previous {
                    line.addLine(to: point)
                    if let delta = deltas[row], delta >= 30 {
                        let label = Text(String(format: "+%.0f ms", delta))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(delta >= 80 ? Color.red : Color.orange)
                        context.draw(label, at: CGPoint(x: (previous.x + point.x) / 2 + 8, y: (previous.y + point.y) / 2),
                                     anchor: .leading)
                    }
                } else {
                    line.move(to: point)
                }
                previous = point
            }
            context.stroke(line, with: .color(.primary.opacity(0.6)), lineWidth: 1.3)

            for (row, rowStats) in stats.enumerated() {
                if let average = rowStats.avg {
                    let dot = CGRect(x: x(average) - 5, y: y(row) - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: dot), with: .color(LatencyLevel.color(average)))
                    context.stroke(Path(ellipseIn: dot), with: .color(.primary.opacity(0.7)), lineWidth: 1.2)
                }
                if let last = rowStats.last {
                    context.fill(Path(ellipseIn: CGRect(x: x(last) - 3, y: y(row) - 3, width: 6, height: 6)),
                                 with: .color(.blue))
                }
            }
        }
        .frame(height: rowHeight * CGFloat(stats.count))
        .gesture(
            SpatialTapGesture().onEnded { tap in
                let row = Int(tap.location.y / rowHeight)
                if row < hopCount { selectedHop = hops[row].hop } else { selectedHop = nil }
            }
        )
    }
}

/// Latency of one hop (or the target) over time: a black line on green, yellow and red zones,
/// with a red vertical line for every packet that got no answer.
struct TimelineGraph: View {
    let samples: [PingSample]
    let window: Int

    var body: some View {
        let shown = samples.reduced(to: 400)
        let answered = shown.filter { $0.latencyMs != nil }
        let slowest = shown.compactMap(\.latencyMs).max() ?? 0
        let top = max(200, (slowest * 1.1 / 50).rounded(.up) * 50)
        let domain = LatencyBars.timeDomain(window: window, firstDate: shown.first?.date)

        Chart {
            RectangleMark(xStart: .value("Von", domain.lowerBound), xEnd: .value("Bis", domain.upperBound),
                          yStart: .value("ms", 0), yEnd: .value("ms", 100))
                .foregroundStyle(.green.opacity(0.16))
            RectangleMark(xStart: .value("Von", domain.lowerBound), xEnd: .value("Bis", domain.upperBound),
                          yStart: .value("ms", 100), yEnd: .value("ms", 200))
                .foregroundStyle(.yellow.opacity(0.2))
            if top > 200 {
                RectangleMark(xStart: .value("Von", domain.lowerBound), xEnd: .value("Bis", domain.upperBound),
                              yStart: .value("ms", 200), yEnd: .value("ms", top))
                    .foregroundStyle(.red.opacity(0.16))
            }
            ForEach(shown.filter { $0.latencyMs == nil }) { lost in
                RuleMark(x: .value("Zeit", lost.date), yStart: .value("ms", 0), yEnd: .value("ms", top))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(answered) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("ms", sample.latencyMs ?? 0))
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: domain)
        .chartYAxisLabel("Latenz (ms)")
        .chartLegend(.hidden)
    }
}
