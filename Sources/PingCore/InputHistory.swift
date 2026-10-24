public struct HistoryItem: Codable, Equatable {
    public let kind: CheckKind
    public let text: String

    public init(kind: CheckKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The hosts and web addresses that were entered last, newest first, for suggestions in the input field.
public struct InputHistory: Codable, Equatable {
    public static let limit = 50

    public private(set) var items: [HistoryItem]

    public init(items: [HistoryItem] = []) {
        self.items = Array(items.prefix(Self.limit))
    }

    /// Puts an entry at the front. An entry that is already there moves up instead of appearing twice.
    public mutating func record(_ text: String, kind: CheckKind) {
        items.removeAll { $0.kind == kind && $0.text.caseInsensitiveCompare(text) == .orderedSame }
        items.insert(HistoryItem(kind: kind, text: text), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    /// Entries of the given kind that contain what has been typed so far, newest first.
    /// Without any text, the most recent entries come back.
    public func suggestions(for typed: String, kind: CheckKind, limit: Int = 8) -> [String] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return items
            .filter { $0.kind == kind }
            .map(\.text)
            .filter { text in
                let lower = text.lowercased()
                return lower != needle && (needle.isEmpty || lower.contains(needle))
            }
            .prefix(limit)
            .map { $0 }
    }
}
