import Foundation

// What the shortcut sheet does beyond listing the menus, in the way KeyClu does it:
// a double press of ⌘ as the trigger, favourites and hidden shortcuts for each app,
// shortcuts written down by hand, and the ones macOS answers everywhere.

/// How ⌘ opens the sheet.
public enum SheetTrigger: String, Codable, Sendable, CaseIterable {
    /// Hold ⌘ alone.
    case hold
    /// Press ⌘ twice and keep the second press down.
    case doubleHold
    /// ⌘ does nothing; only the sheet's own shortcut opens it.
    case shortcutOnly
}

/// The sheet's look.
public enum SheetAppearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

/// A shortcut the menus do not show, written down by hand.
public struct CustomSheetShortcut: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var keys: String
    /// The app it belongs to; nil shows it in every app.
    public var bundleID: String?

    public init(title: String, keys: String, bundleID: String? = nil) {
        self.title = title
        self.keys = keys
        self.bundleID = bundleID
    }
}

/// What one app's sheet keeps in front and what it leaves out, by `sheetKey`.
public struct SheetMarks: Codable, Equatable, Sendable {
    public var starred: [String] = []
    public var hidden: [String] = []

    public init(starred: [String] = [], hidden: [String] = []) {
        self.starred = starred
        self.hidden = hidden
    }

    public var isEmpty: Bool { starred.isEmpty && hidden.isEmpty }

    public mutating func toggleStar(_ key: String) {
        if let index = starred.firstIndex(of: key) { starred.remove(at: index) } else { starred.append(key) }
    }

    public mutating func toggleHidden(_ key: String) {
        if let index = hidden.firstIndex(of: key) {
            hidden.remove(at: index)
        } else {
            hidden.append(key)
            starred.removeAll { $0 == key }
        }
    }
}

/// Names a shortcut by its menu, so a mark survives the sheet being read again.
public func sheetKey(group: String, shortcut: SheetShortcut) -> String {
    group + "\u{1}" + shortcut.id
}

/// The names of the groups the sheet adds itself.
public struct SheetGroupTitles: Equatable, Sendable {
    public var favourites: String
    public var mine: String
    public var system: String

    public init(favourites: String, mine: String, system: String) {
        self.favourites = favourites
        self.mine = mine
        self.system = system
    }
}

/// Puts the sheet in order: the favourites first, then the shortcuts written down by
/// hand, then the menus without what was hidden, then the system's. Every menu shortcut
/// carries its `origin`, in the favourites too, so a click still finds its menu item.
public func arrangedSheet(_ groups: [SheetGroup], marks: SheetMarks, custom: [SheetShortcut], system: [SheetShortcut],
                          showHidden: Bool, titles: SheetGroupTitles) -> [SheetGroup] {
    let hidden = Set(marks.hidden)
    var byKey: [String: SheetShortcut] = [:]
    var menus: [SheetGroup] = []
    for group in groups {
        var kept: [SheetShortcut] = []
        for var shortcut in group.shortcuts {
            let key = sheetKey(group: group.title, shortcut: shortcut)
            shortcut.origin = key
            byKey[key] = shortcut
            if showHidden || !hidden.contains(key) { kept.append(shortcut) }
        }
        if !kept.isEmpty { menus.append(SheetGroup(title: group.title, shortcuts: kept)) }
    }
    var result: [SheetGroup] = []
    let favourites = marks.starred.compactMap { byKey[$0] }
    if !favourites.isEmpty { result.append(SheetGroup(title: titles.favourites, shortcuts: favourites)) }
    if !custom.isEmpty { result.append(SheetGroup(title: titles.mine, shortcuts: custom)) }
    result += menus
    if !system.isEmpty { result.append(SheetGroup(title: titles.system, shortcuts: system)) }
    return result
}

/// The hand-written shortcuts that show in the app with this bundle identifier.
public func customShortcuts(_ all: [CustomSheetShortcut], for bundleID: String?) -> [SheetShortcut] {
    all.filter { !$0.title.isEmpty && !$0.keys.isEmpty && ($0.bundleID == nil || $0.bundleID == bundleID) }
        .map { SheetShortcut(title: $0.title, keys: $0.keys) }
}

/// Decides when ⌘ was pressed twice and the second press is still down. The first press
/// has to be a short tap of ⌘ alone, and the second has to follow soon after it.
public struct CommandDoubleHold: Equatable, Sendable {
    /// The longest a tap may last, and the longest pause after it, in seconds.
    public var window: Double
    public private(set) var generation = 0
    public private(set) var isHolding = false
    private var isDown = false
    private var tapStart: Double?
    private var tapEnd: Double?

    public init(window: Double = 0.4) {
        self.window = window
    }

    /// The modifiers changed at `time`. Returns the generation to wait on when the
    /// second press just went down, nil otherwise.
    public mutating func flagsChanged(command: Bool, others: Bool, at time: Double) -> Int? {
        let alone = command && !others
        if alone {
            guard !isDown else { return nil }
            isDown = true
            if let tapEnd, time - tapEnd <= window {
                self.tapEnd = nil
                isHolding = true
                generation += 1
                return generation
            }
            tapStart = time
            tapEnd = nil
            return nil
        }
        let wasTap = isDown && !isHolding && !command && !others
        if wasTap, let tapStart, time - tapStart <= window { tapEnd = time } else { tapEnd = nil }
        tapStart = nil
        isDown = false
        isHolding = false
        generation += 1
        return nil
    }

    /// A key or a mouse button went down: a shortcut is being typed.
    public mutating func interrupted() {
        generation += 1
        tapStart = nil
        tapEnd = nil
    }

    public func shouldFire(_ generation: Int) -> Bool {
        isHolding && generation == self.generation
    }
}

/// The column count the sheet uses: the chosen one, or what the screen's width holds.
public func sheetColumnCount(chosen: Int, screenWidth: Double, hasShortcuts: Bool) -> Int {
    guard hasShortcuts else { return 1 }
    let fits = max(1, Int((screenWidth - 128) / 300))
    if chosen > 0 { return min(chosen, fits) }
    return min(4, max(2, Int(screenWidth / 330)))
}

/// The shortcuts macOS answers in every app, with its default keys.
func systemSheetShortcuts() -> [SheetShortcut] {
    [
        (String(localized: "Spotlight", bundle: .module), "⌘Space"),
        (String(localized: "Switch apps", bundle: .module), "⌘⇥"),
        (String(localized: "Switch windows of the app", bundle: .module), "⌘`"),
        (String(localized: "Mission Control", bundle: .module), "⌃↑"),
        (String(localized: "App windows", bundle: .module), "⌃↓"),
        (String(localized: "Move a Space left or right", bundle: .module), "⌃← ⌃→"),
        (String(localized: "Screenshot of the screen", bundle: .module), "⇧⌘3"),
        (String(localized: "Screenshot of a selection", bundle: .module), "⇧⌘4"),
        (String(localized: "Screenshot and recording options", bundle: .module), "⇧⌘5"),
        (String(localized: "Force quit apps", bundle: .module), "⌥⌘⎋"),
        (String(localized: "Lock the screen", bundle: .module), "⌃⌘Q"),
        (String(localized: "Emoji and symbols", bundle: .module), "⌃⌘Space"),
        (String(localized: "Show or hide the Dock", bundle: .module), "⌥⌘D"),
        (String(localized: "Hide the app", bundle: .module), "⌘H"),
        (String(localized: "Hide the other apps", bundle: .module), "⌥⌘H"),
        (String(localized: "Quit the app", bundle: .module), "⌘Q"),
    ].map { SheetShortcut(title: $0.0, keys: $0.1) }
}
