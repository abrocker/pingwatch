import Foundation

/// How a host is checked: with an ICMP ping, or by loading a web page over HTTP(S).
public enum CheckKind: String, Codable, CaseIterable {
    case ping, web
}

public struct HostEntry: Identifiable, Codable, Equatable {
    public var id = UUID()
    /// The host or IP for a ping, the full URL for a web check.
    public var name: String
    public var enabled = true
    public var kind: CheckKind = .ping
    /// Seconds between two checks of this host; nil uses the default for its kind.
    public var interval: Int?

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, kind: CheckKind = .ping, interval: Int? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.kind = kind
        self.interval = interval
    }

    // Hosts saved by earlier versions have no "kind" and are pings.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try container.decodeIfPresent(CheckKind.self, forKey: .kind) ?? .ping
        interval = try container.decodeIfPresent(Int.self, forKey: .interval)
    }

    /// The machine behind the entry, used for DNS and the route.
    public var hostName: String {
        kind == .web ? (WebTarget.host(of: name) ?? name) : name
    }
}
