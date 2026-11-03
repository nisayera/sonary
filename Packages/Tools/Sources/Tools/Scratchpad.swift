import Foundation

public struct ScratchpadTab: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String = "") {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// A file name for an exported note: the title, with anything a file system dislikes removed.
public func exportFileName(for title: String, fallback: String = "Note") -> String {
    let cleaned = title
        .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    let name = cleaned.isEmpty ? fallback : String(cleaned.prefix(60))
    return "\(name).md"
}

/// A note's first line makes a better tab title than "Untitled" once something is written.
public func suggestedTitle(for text: String, fallback: String) -> String {
    let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    let cleaned = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
    return cleaned.isEmpty ? fallback : String(cleaned.prefix(28))
}

/// Moves one tab in the list; out-of-range indexes leave it as it was.
public func movedTab(_ tabs: [ScratchpadTab], from source: Int, to destination: Int) -> [ScratchpadTab] {
    guard tabs.indices.contains(source), destination >= 0, destination < tabs.count, source != destination else { return tabs }
    var result = tabs
    let tab = result.remove(at: source)
    result.insert(tab, at: destination)
    return result
}
