import Foundation

public enum ReverseDNS {
    /// The hostname for an IP address, or nil if there is none.
    public static func lookup(_ address: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_flags = AI_NUMERICHOST
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(address, nil, &hints, &result) == 0, let info = result else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(result) }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen,
                                         &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
                continuation.resume(returning: status == 0 ? String(cString: buffer) : nil)
            }
        }
    }
}

public enum ForwardDNS {
    /// The IP address a hostname resolves to (IPv4 preferred), or nil if it does not resolve.
    public static func lookup(_ host: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(result) }

                var chosen = first
                var node: UnsafeMutablePointer<addrinfo>? = first
                while let current = node {
                    if current.pointee.ai_family == AF_INET { chosen = current; break }
                    node = current.pointee.ai_next
                }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(chosen.pointee.ai_addr, chosen.pointee.ai_addrlen,
                                         &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                continuation.resume(returning: status == 0 ? String(cString: buffer) : nil)
            }
        }
    }
}
