import Foundation

/// "#RRGGBB" from 0...1 components (clamped).
public func hexColor(red: Double, green: Double, blue: Double) -> String {
    func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
}

/// Fuzzy score for the command bar: higher is better, nil means no match.
/// Prefix matches beat word-start matches beat in-order letter matches.
public func matchScore(_ query: String, in text: String) -> Int? {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    let t = text.lowercased()
    guard !q.isEmpty else { return 0 }
    if t.hasPrefix(q) { return 1000 - t.count }
    if t.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 800 - t.count }
    if t.contains(q) { return 600 - t.count }
    var index = t.startIndex
    var gaps = 0
    for ch in q {
        guard let found = t[index...].firstIndex(of: ch) else { return nil }
        gaps += t.distance(from: index, to: found)
        index = t.index(after: found)
    }
    return 400 - gaps - t.count
}

public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// Replaces {date}, {time} and {clipboard} placeholders in a snippet.
public func expandSnippet(_ text: String, now: Date, clipboard: String?, locale: Locale = .current) -> String {
    let date = now.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    return text
        .replacingOccurrences(of: "{date}", with: date)
        .replacingOccurrences(of: "{time}", with: time)
        .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
}

/// Joins Vision text lines, keeping the reading order.
public func joinRecognizedLines(_ lines: [String]) -> String {
    lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
}
