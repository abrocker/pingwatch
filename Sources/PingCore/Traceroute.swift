import Foundation

/// One line of a traceroute: the router at this hop and how long it took to answer.
public struct HopReading: Equatable {
    public let hop: Int
    public let address: String?
    public let latencyMs: Double?

    public init(hop: Int, address: String?, latencyMs: Double?) {
        self.hop = hop
        self.address = address
        self.latencyMs = latencyMs
    }
}

public enum Traceroute {
    /// Traces the route with one probe per hop. A silent router costs `waitSeconds` before traceroute moves on,
    /// so the hop range is split into small parts that run side by side: a path with many silent routers
    /// takes a few seconds instead of twenty.
    public static func run(host: String, maxHops: Int = 20, waitSeconds: Int = 1, hopsPerProcess: Int = 3) async -> [HopReading] {
        guard HostName.isValid(host) else { return [] }
        let isIPv6 = host.contains(":")
        let tool = isIPv6 ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute"
        // IPv6 is traced in one piece; its tool has not been verified with split ranges.
        let step = isIPv6 ? maxHops : max(1, hopsPerProcess)
        let timeout = Double(step * (waitSeconds + 1) + 10)

        let outputs = await withTaskGroup(of: String.self) { group in
            for first in stride(from: 1, through: maxHops, by: step) {
                let last = min(first + step - 1, maxHops)
                let args = ["-n", "-q", "1", "-w", "\(waitSeconds)", "-f", "\(first)", "-m", "\(last)", host]
                group.addTask {
                    await ProcessRunner.run(tool, args, timeout: timeout, includeStandardError: true)?.output ?? ""
                }
            }
            var collected: [String] = []
            for await output in group { collected.append(output) }
            return collected
        }
        return merge(outputs)
    }

    /// Combines the outputs of several traceroute runs over consecutive hop ranges into one route.
    /// A range that starts behind the destination reports the destination again; those hops are cut off.
    public static func merge(_ outputs: [String]) -> [HopReading] {
        var byHop: [Int: HopReading] = [:]
        for reading in outputs.flatMap(parse) where byHop[reading.hop] == nil {
            byHop[reading.hop] = reading
        }
        var readings = byHop.values.sorted { $0.hop < $1.hop }
        if let target = outputs.compactMap(destination).first,
           let reached = readings.first(where: { $0.address == target }) {
            readings.removeAll { $0.hop > reached.hop }
        }
        return readings
    }

    /// The address from the header line, e.g. "traceroute to www.apple.com (23.1.2.3), 20 hops max".
    public static func destination(in output: String) -> String? {
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("traceroute") }),
              let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { return nil }
        return String(line[line.index(after: open)..<close])
    }

    /// Parses `traceroute -n -q 1` output, e.g. " 2  100.124.1.52  12.002 ms" or " 3  *".
    public static func parse(_ output: String) -> [HopReading] {
        var seen = Set<Int>()
        var readings: [HopReading] = []
        for line in output.split(separator: "\n") {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = tokens.first, let hop = Int(first), seen.insert(hop).inserted else { continue }
            let rest = Array(tokens.dropFirst())
            let address = rest.first.flatMap { $0 == "*" ? nil : $0 }
            var latency: Double?
            if let i = rest.firstIndex(of: "ms"), i > 0 { latency = Double(rest[i - 1]) }
            readings.append(HopReading(hop: hop, address: address, latencyMs: address == nil ? nil : latency))
        }
        return readings
    }
}
