import Foundation

public enum WebTarget {
    /// A full http(s) URL from whatever the user typed: "example.com/page" becomes "https://example.com/page",
    /// an explicit http:// or https:// is kept. Nil for other schemes or an unusable host.
    public static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            guard !text.contains("://") else { return nil }
            if text.hasPrefix("//") { text.removeFirst(2) }
            text = "https://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, HostName.isValid(host) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        return components.string
    }

    /// The host part of a URL, e.g. "www.example.com".
    public static func host(of url: String) -> String? {
        URLComponents(string: url)?.host
    }
}

public enum HTTPStatus {
    /// "HTTP 200 OK", or just "HTTP 418" for codes without a description.
    public static func summary(_ code: Int) -> String {
        let description = text(code)
        return description.isEmpty ? "HTTP \(code)" : "HTTP \(code) \(description)"
    }

    /// Short German description of common status codes; empty for the rest.
    public static func text(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return String(localized: "Erstellt")
        case 204: return String(localized: "Kein Inhalt")
        case 301: return String(localized: "Dauerhaft verschoben")
        case 302: return String(localized: "Weitergeleitet")
        case 304: return String(localized: "Nicht geändert")
        case 400: return String(localized: "Ungültige Anfrage")
        case 401: return String(localized: "Nicht autorisiert")
        case 403: return String(localized: "Verboten")
        case 404: return String(localized: "Nicht gefunden")
        case 408: return String(localized: "Zeitüberschreitung")
        case 429: return String(localized: "Zu viele Anfragen")
        case 500: return String(localized: "Serverfehler")
        case 502: return "Bad Gateway"
        case 503: return String(localized: "Nicht verfügbar")
        case 504: return String(localized: "Gateway-Zeitüberschreitung")
        default: return ""
        }
    }
}

public struct WebResult: Equatable {
    public let statusCode: Int?
    /// Time until the whole response had arrived, including DNS, connect and TLS.
    public let latencyMs: Double?
    public let error: String?

    public init(statusCode: Int?, latencyMs: Double?, error: String?) {
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.error = error
    }

    /// The page counts as working when the server answers with a 2xx status.
    public var isOK: Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode)
    }

    /// "HTTP 200 OK", "HTTP 503 Nicht verfügbar", or the error, e.g. "Zeitüberschreitung".
    public var summary: String {
        guard let statusCode else { return error ?? String(localized: "Keine Antwort") }
        return HTTPStatus.summary(statusCode)
    }
}

public enum WebChecker {
    /// Loads the page once (GET, redirects followed) and reports status code and load time.
    /// Every check uses a fresh connection, so DNS and TLS problems show up in the time.
    public static func check(_ urlString: String, timeout: TimeInterval = 10) async -> WebResult {
        guard let url = URL(string: urlString) else {
            return WebResult(statusCode: nil, latencyMs: nil, error: String(localized: "Ungültige Adresse"))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.setValue("PingWatch/1.0", forHTTPHeaderField: "User-Agent")

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            guard let http = response as? HTTPURLResponse else {
                return WebResult(statusCode: nil, latencyMs: nil, error: String(localized: "Keine HTTP-Antwort"))
            }
            return WebResult(statusCode: http.statusCode, latencyMs: elapsed, error: nil)
        } catch {
            return WebResult(statusCode: nil, latencyMs: nil, error: describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut: return String(localized: "Zeitüberschreitung")
        case .cannotFindHost, .dnsLookupFailed: return String(localized: "Host nicht gefunden")
        case .cannotConnectToHost: return String(localized: "Verbindung abgelehnt")
        case .networkConnectionLost: return String(localized: "Verbindung abgebrochen")
        case .notConnectedToInternet: return String(localized: "Kein Netzwerk")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return String(localized: "TLS-/Zertifikatsfehler")
        default: return urlError.localizedDescription
        }
    }
}
