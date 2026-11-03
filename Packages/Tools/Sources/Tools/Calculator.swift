import Foundation

/// Works out a plain arithmetic expression like "12*(3+4)/2". Nil when the text is not maths,
/// so the command bar can fall through to its other results. Written by hand rather than handed
/// to NSExpression, which raises an Objective-C exception on malformed input and would take the app down.
public func evaluateExpression(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard trimmed.count >= 3,
          trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^")) != nil,
          trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
          trimmed.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.+-*/()^ ").contains($0) })
    else { return nil }
    var parser = ExpressionParser(Array(trimmed))
    guard let value = parser.parse(), value.isFinite else { return nil }
    return formatNumber(value)
}

/// Recursive descent over + - * / ^ with parentheses and a leading minus.
private struct ExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(_ characters: [Character]) {
        self.characters = characters
    }

    mutating func parse() -> Double? {
        guard let value = sum() else { return nil }
        skipSpaces()
        return index == characters.count ? value : nil
    }

    private mutating func sum() -> Double? {
        guard var value = product() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            index += 1
            guard let next = product() else { return nil }
            value = op == "+" ? value + next : value - next
        }
        return value
    }

    private mutating func product() -> Double? {
        guard var value = power() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            index += 1
            guard let next = power() else { return nil }
            if op == "/" {
                guard next != 0 else { return nil }
                value /= next
            } else {
                value *= next
            }
        }
        return value
    }

    private mutating func power() -> Double? {
        guard let base = term() else { return nil }
        guard peek() == "^" else { return base }
        index += 1
        guard let exponent = power() else { return nil }
        return pow(base, exponent)
    }

    private mutating func term() -> Double? {
        skipSpaces()
        if peek() == "-" {
            index += 1
            guard let value = term() else { return nil }
            return -value
        }
        if peek() == "(" {
            index += 1
            guard let value = sum() else { return nil }
            skipSpaces()
            guard peek() == ")" else { return nil }
            index += 1
            return value
        }
        var digits = ""
        while let character = peek(), character.isNumber || character == "." {
            digits.append(character)
            index += 1
        }
        return digits.isEmpty ? nil : Double(digits)
    }

    private mutating func skipSpaces() {
        while index < characters.count, characters[index] == " " { index += 1 }
    }

    private mutating func peek() -> Character? {
        skipSpaces()
        return index < characters.count ? characters[index] : nil
    }
}

/// Up to six decimals, without trailing zeros.
public func formatNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
    var text = String(format: "%.6f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

private let lengthUnits: [String: UnitLength] = [
    "mm": .millimeters, "cm": .centimeters, "m": .meters, "km": .kilometers,
    "in": .inches, "inch": .inches, "ft": .feet, "foot": .feet, "yd": .yards, "mi": .miles, "mile": .miles,
]
private let massUnits: [String: UnitMass] = [
    "g": .grams, "kg": .kilograms, "t": .metricTons, "oz": .ounces, "lb": .pounds, "lbs": .pounds, "st": .stones,
]
private let temperatureUnits: [String: UnitTemperature] = [
    "c": .celsius, "°c": .celsius, "f": .fahrenheit, "°f": .fahrenheit, "k": .kelvin,
]
private let dataUnits: [String: UnitInformationStorage] = [
    "b": .bytes, "kb": .kilobytes, "mb": .megabytes, "gb": .gigabytes, "tb": .terabytes,
    "kib": .kibibytes, "mib": .mebibytes, "gib": .gibibytes,
]

/// Converts "10 km in mi", "20 °C to F", "5 lb in kg", "700 mb in gib". Nil when it is not a conversion.
public func convertUnits(_ text: String) -> String? {
    let parts = text.lowercased()
        .replacingOccurrences(of: " to ", with: " in ")
        .split(separator: " ", omittingEmptySubsequences: true)
        .map(String.init)
    guard parts.count >= 3, let separator = parts.firstIndex(of: "in"), separator >= 1, separator + 1 < parts.count else {
        return nil
    }
    let valueText = parts[0..<separator].joined().replacingOccurrences(of: ",", with: ".")
    let fromName = String(valueText.drop(while: { $0.isNumber || $0 == "." || $0 == "-" }))
    let numberText = String(valueText.prefix(valueText.count - fromName.count))
    guard let value = Double(numberText) else { return nil }
    let toName = parts[(separator + 1)...].joined()
    let sourceName = fromName.isEmpty ? (separator >= 2 ? parts[separator - 1] : "") : fromName

    if let from = lengthUnits[sourceName], let to = lengthUnits[toName] {
        return format(Measurement(value: value, unit: from).converted(to: to))
    }
    if let from = massUnits[sourceName], let to = massUnits[toName] {
        return format(Measurement(value: value, unit: from).converted(to: to))
    }
    if let from = temperatureUnits[sourceName], let to = temperatureUnits[toName] {
        return format(Measurement(value: value, unit: from).converted(to: to))
    }
    if let from = dataUnits[sourceName], let to = dataUnits[toName] {
        return format(Measurement(value: value, unit: from).converted(to: to))
    }
    return nil
}

private func format<U: Unit>(_ measurement: Measurement<U>) -> String {
    "\(formatNumber(measurement.value)) \(measurement.unit.symbol)"
}

public struct EmojiItem: Equatable, Sendable {
    public var emoji: String
    public var name: String
}

/// A small, hand-picked set: enough to be useful in the command bar without shipping a database.
public let emojiCatalogue: [EmojiItem] = [
    EmojiItem(emoji: "😀", name: "grin smile happy"), EmojiItem(emoji: "😂", name: "laugh tears joy"),
    EmojiItem(emoji: "🙂", name: "smile slight"), EmojiItem(emoji: "😉", name: "wink"),
    EmojiItem(emoji: "😍", name: "love heart eyes"), EmojiItem(emoji: "🤔", name: "think hmm"),
    EmojiItem(emoji: "😅", name: "sweat nervous laugh"), EmojiItem(emoji: "😭", name: "cry sob"),
    EmojiItem(emoji: "😎", name: "cool sunglasses"), EmojiItem(emoji: "🙄", name: "eyeroll"),
    EmojiItem(emoji: "👍", name: "thumbs up ok yes"), EmojiItem(emoji: "👎", name: "thumbs down no"),
    EmojiItem(emoji: "🙏", name: "please thanks pray"), EmojiItem(emoji: "👏", name: "clap applause"),
    EmojiItem(emoji: "🤝", name: "handshake deal"), EmojiItem(emoji: "💪", name: "strong muscle"),
    EmojiItem(emoji: "❤️", name: "heart love red"), EmojiItem(emoji: "🔥", name: "fire hot lit"),
    EmojiItem(emoji: "✨", name: "sparkles shiny new"), EmojiItem(emoji: "🎉", name: "party tada celebrate"),
    EmojiItem(emoji: "🚀", name: "rocket ship launch"), EmojiItem(emoji: "💡", name: "idea bulb light"),
    EmojiItem(emoji: "⚠️", name: "warning caution"), EmojiItem(emoji: "✅", name: "check done yes"),
    EmojiItem(emoji: "❌", name: "cross no wrong"), EmojiItem(emoji: "🐛", name: "bug issue"),
    EmojiItem(emoji: "💻", name: "laptop computer code"), EmojiItem(emoji: "📝", name: "note memo write"),
    EmojiItem(emoji: "📦", name: "package box release"), EmojiItem(emoji: "⏰", name: "alarm clock time"),
    EmojiItem(emoji: "☕️", name: "coffee break"), EmojiItem(emoji: "🍕", name: "pizza food"),
    EmojiItem(emoji: "🚲", name: "bike bicycle ride"), EmojiItem(emoji: "🏔️", name: "mountain trail"),
    EmojiItem(emoji: "🎧", name: "headphones music"), EmojiItem(emoji: "🔧", name: "wrench fix tool"),
]

/// Emoji whose name contains the query, best match first.
public func searchEmoji(_ query: String, in catalogue: [EmojiItem] = emojiCatalogue) -> [EmojiItem] {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard q.count >= 2 else { return [] }
    return catalogue.compactMap { item -> (EmojiItem, Int)? in
        guard let score = matchScore(q, in: item.name) else { return nil }
        return (item, score)
    }
    .sorted { $0.1 > $1.1 }
    .map(\.0)
}
