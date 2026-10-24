import Foundation

public struct PingResult: Equatable {
    public let reachable: Bool
    public let latencyMs: Double?
}

public enum HostName {
    /// Hostnames and IPv4/IPv6 addresses only. Rejects anything `ping` could read as an option.
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 253, !name.hasPrefix("-") else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_:%".contains($0)) }
    }

    /// The host part of whatever the user typed: "https://www.example.com:8443/a?b=1" gives
    /// "www.example.com". Plain hostnames and IPv4/IPv6 addresses pass through. Nil if nothing usable is left.
    public static func extract(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
        } else if text.hasPrefix("//") {
            text = String(text.dropFirst(2))
        }
        if let end = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<end]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: text.startIndex)..<close])
        } else if text.filter({ $0 == ":" }).count == 1, let colon = text.firstIndex(of: ":") {
            text = String(text[..<colon])
        }
        while text.hasSuffix(".") { text.removeLast() }
        return isValid(text) ? text : nil
    }
}

public enum Pinger {
    public static func ping(host: String, timeoutMs: Int = 2000) async -> PingResult {
        let failure = PingResult(reachable: false, latencyMs: nil)
        guard HostName.isValid(host) else { return failure }
        let tool = host.contains(":") ? "/sbin/ping6" : "/sbin/ping"
        let args = host.contains(":")
            ? ["-c", "1", host]
            : ["-c", "1", "-W", "\(timeoutMs)", "-t", "\(timeoutMs / 1000 + 2)", host]

        guard let result = await ProcessRunner.run(tool, args, timeout: Double(timeoutMs) / 1000 + 6) else {
            return failure
        }
        let reachable = result.status == 0
        return PingResult(reachable: reachable, latencyMs: reachable ? parseLatency(result.output) : nil)
    }

    static func parseLatency(_ output: String) -> Double? {
        guard let range = output.range(of: #"time[=<]([0-9.]+)"#, options: .regularExpression) else { return nil }
        let digits = output[range].drop { !$0.isNumber }
        return Double(digits)
    }
}
