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
    /// Typed anywhere, such as ";sig", it is replaced by the snippet. Optional, so snippets
    /// saved before triggers existed still read.
    public var trigger: String?

    public init(id: UUID = UUID(), title: String, text: String, trigger: String? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.trigger = trigger
    }
}

/// Replaces {date}, {time} and {clipboard} placeholders in a snippet, and {date:FORMAT} or
/// {time:FORMAT} with the date in a pattern of the user's own, such as {date:yyyy-MM-dd}.
public func expandSnippet(_ text: String, now: Date, clipboard: String?, locale: Locale = .current) -> String {
    let date = now.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    let custom = text.replacing(#/\{(?:date|time):([^}]+)\}/#) { match in
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = String(match.1)
        return formatter.string(from: now)
    }
    return custom
        .replacingOccurrences(of: "{date}", with: date)
        .replacingOccurrences(of: "{time}", with: time)
        .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
}

/// Watches what is typed and notices when it ends in a snippet's trigger.
public struct SnippetTriggerWatcher: Sendable {
    /// The shortest trigger that counts: a single character would fire all the time.
    public static let minimumTriggerLength = 2
    private var typed = ""
    private let limit = 64

    public init() {}

    /// Adds what a key press typed and returns the snippet whose trigger the text now ends
    /// with, the longest one when several do (";sig2" before ";sig").
    public mutating func type(_ characters: String, snippets: [Snippet]) -> Snippet? {
        guard !characters.isEmpty else { return nil }
        typed += characters
        if typed.count > limit { typed = String(typed.suffix(limit)) }
        let candidates = snippets.filter { ($0.trigger ?? "").count >= Self.minimumTriggerLength }
            .sorted { ($0.trigger ?? "").count > ($1.trigger ?? "").count }
        guard let match = candidates.first(where: { typed.hasSuffix($0.trigger ?? "") }) else { return nil }
        typed = ""
        return match
    }

    public mutating func backspace() {
        if !typed.isEmpty { typed.removeLast() }
    }

    /// A click, an arrow key or a shortcut: the cursor may be somewhere else now.
    public mutating func reset() {
        typed = ""
    }
}

/// Joins Vision text lines, keeping the reading order.
public func joinRecognizedLines(_ lines: [String]) -> String {
    lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
}

/// How a snippet reaches the app: typed where the cursor is, or put on the clipboard
/// for the user to paste.
public enum SnippetDelivery: String, CaseIterable, Codable, Sendable, Identifiable {
    case type, clipboard

    public var id: String { rawValue }
}
