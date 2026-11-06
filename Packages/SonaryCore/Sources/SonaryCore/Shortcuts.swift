import Carbon.HIToolbox
import Foundation
import Observation

/// One keyboard shortcut: a key code plus Carbon modifier flags.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut the user switched off: nothing is registered for it.
    public static let none = KeyCombo(keyCode: -1, modifiers: 0)

    public var isEmpty: Bool { keyCode < 0 }

    /// At least one modifier, or the shortcut would swallow a plain key everywhere.
    public var isUsable: Bool { !isEmpty && modifiers != 0 }
}

/// Carbon modifier flags, named so call sites read like the keys they stand for.
public enum KeyModifier {
    public static let command = 256
    public static let shift = 512
    public static let option = 2048
    public static let control = 4096
}

/// What the user sees for a shortcut: "⌃⌥T", or an empty string when it is off.
public func shortcutDisplay(_ combo: KeyCombo) -> String {
    guard !combo.isEmpty else { return "" }
    var text = ""
    if combo.modifiers & KeyModifier.control != 0 { text += "⌃" }
    if combo.modifiers & KeyModifier.option != 0 { text += "⌥" }
    if combo.modifiers & KeyModifier.shift != 0 { text += "⇧" }
    if combo.modifiers & KeyModifier.command != 0 { text += "⌘" }
    return text + keyName(combo.keyCode)
}

/// The printed name of a key code. Unknown codes show their number, which is still
/// better than an empty box.
public func keyName(_ keyCode: Int) -> String {
    let named: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    if let name = named[keyCode] { return name }
    let letters: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
    ]
    return letters[keyCode] ?? "#\(keyCode)"
}

/// A shortcut a module offers: its stable identifier, the name the settings page
/// shows and the combination it ships with.
public struct ShortcutDefinition: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var group: String
    public var defaultCombo: KeyCombo

    public init(id: String, title: String, group: String, defaultCombo: KeyCombo) {
        self.id = id
        self.title = title
        self.group = group
        self.defaultCombo = defaultCombo
    }
}

/// Everything a shortcut can be rejected for, so the recorder can say why.
public enum ShortcutProblem: Equatable, Sendable {
    case needsModifier
    case takenBy(String)
}

/// Whether a combination can be used for this shortcut, given what the others hold.
public func shortcutProblem(_ combo: KeyCombo, for id: String,
                            taken: [String: KeyCombo], titles: [String: String]) -> ShortcutProblem? {
    guard !combo.isEmpty else { return nil }
    guard combo.isUsable else { return .needsModifier }
    for (other, existing) in taken where other != id && existing == combo {
        return .takenBy(titles[other] ?? other)
    }
    return nil
}

/// Every Sonary shortcut in one place: the modules say what they offer and what to run,
/// this keeps the user's changes and owns the registrations.
@MainActor
@Observable
public final class ShortcutStore {
    public static let shared = ShortcutStore()

    public private(set) var definitions: [ShortcutDefinition] = []

    @ObservationIgnored private var defaults: UserDefaults = .standard
    @ObservationIgnored private var custom: [String: KeyCombo] = [:]
    @ObservationIgnored private var actions: [String: () -> Void] = [:]
    @ObservationIgnored private var registered: [String: HotKey] = [:]

    private static let storageKey = "shortcuts.custom"

    public init(defaults: UserDefaults = .standard) {
        configure(defaults: defaults)
    }

    public func configure(defaults: UserDefaults) {
        self.defaults = defaults
        custom = StoredSettings.load([String: KeyCombo].self, key: Self.storageKey, from: defaults, fallback: [:])
    }

    /// Modules announce their shortcuts once, so the settings page can list them even
    /// while the module is switched off.
    public func describe(_ list: [ShortcutDefinition]) {
        for definition in list {
            if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
                definitions[index] = definition
            } else {
                definitions.append(definition)
            }
        }
    }

    /// The combination in force: what the user set, or what the module ships with.
    public func combo(for id: String) -> KeyCombo {
        custom[id] ?? definitions.first { $0.id == id }?.defaultCombo ?? .none
    }

    public func isCustom(_ id: String) -> Bool { custom[id] != nil }

    /// Changes a shortcut. Nil puts the module's own combination back.
    public func set(_ combo: KeyCombo?, for id: String) {
        if let combo { custom[id] = combo } else { custom.removeValue(forKey: id) }
        if let data = try? JSONEncoder().encode(custom) { defaults.set(data, forKey: Self.storageKey) }
        if actions[id] != nil { apply(id) }
    }

    /// A module turns a shortcut on by handing over what it should do.
    public func bind(_ id: String, action: @escaping () -> Void) {
        actions[id] = action
        apply(id)
    }

    public func unbind(_ id: String) {
        actions.removeValue(forKey: id)
        registered.removeValue(forKey: id)?.unregister()
    }

    /// Switches off every shortcut a module owns, for when the module stops.
    public func unbindAll(prefix: String) {
        for id in actions.keys where id.hasPrefix(prefix) { unbind(id) }
    }

    /// What every bound shortcut currently holds, for the recorder's clash check.
    public var inUse: [String: KeyCombo] {
        var result: [String: KeyCombo] = [:]
        for definition in definitions {
            let combo = self.combo(for: definition.id)
            if !combo.isEmpty { result[definition.id] = combo }
        }
        return result
    }

    public var titles: [String: String] {
        Dictionary(definitions.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    private func apply(_ id: String) {
        registered.removeValue(forKey: id)?.unregister()
        let combo = self.combo(for: id)
        guard combo.isUsable, let action = actions[id] else { return }
        if let hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers, action: action) {
            registered[id] = hotKey
        }
    }
}
