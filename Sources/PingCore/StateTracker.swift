public enum HostState: Equatable {
    case unknown, up, down
}

public enum HostEvent: Equatable {
    case becameUp, becameDown
}

/// Turns a stream of ping results into state changes.
/// A host only counts as down after `downAfter` failed pings in a row.
public struct StateTracker {
    public private(set) var state: HostState = .unknown
    public private(set) var failures = 0

    public init() {}

    public mutating func record(success: Bool, downAfter: Int) -> HostEvent? {
        if success {
            failures = 0
            guard state != .up else { return nil }
            state = .up
            return .becameUp
        }
        failures += 1
        guard failures >= max(1, downAfter), state != .down else { return nil }
        state = .down
        return .becameDown
    }
}
