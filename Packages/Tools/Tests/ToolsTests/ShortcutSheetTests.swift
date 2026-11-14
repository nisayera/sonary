import Foundation
import SonaryCore
import Testing
@testable import Tools

struct ShortcutSheetTests {
    @Test func menuKeysReadTheWayMenusPrintThem() {
        #expect(menuShortcutLabel(character: "s", glyph: nil, virtualKey: nil, modifiers: 1) == "⇧⌘S")
        #expect(menuShortcutLabel(character: "q", glyph: nil, virtualKey: nil, modifiers: 6) == "⌃⌥⌘Q")
        // 8 means the shortcut has no ⌘ in it.
        #expect(menuShortcutLabel(character: nil, glyph: 112, virtualKey: nil, modifiers: 8) == "F2")
        #expect(menuShortcutLabel(character: nil, glyph: 23, virtualKey: nil, modifiers: 0) == "⌘⌫")
        #expect(menuShortcutLabel(character: " ", glyph: nil, virtualKey: nil, modifiers: 4) == "⌃⌘Space")
    }

    @Test func itemsWithoutAKeyHaveNoLabel() {
        #expect(menuShortcutLabel(character: nil, glyph: nil, virtualKey: nil, modifiers: 0) == nil)
        #expect(menuShortcutLabel(character: "", glyph: nil, virtualKey: 0, modifiers: 0) == nil)
    }

    private func group(_ name: String, _ count: Int) -> SheetGroup {
        SheetGroup(title: name, shortcuts: (0..<count).map { SheetShortcut(title: "\(name) \($0)", keys: "⌘\($0)") })
    }

    @Test func menusSpreadOverColumnsInOrder() {
        let groups = [group("File", 10), group("Edit", 10), group("View", 10), group("Go", 2)]
        let columns = sheetColumns(groups, count: 3)
        #expect(columns.count == 3)
        #expect(columns.flatMap { $0 }.map(\.title) == ["File", "Edit", "View", "Go"])
        #expect(sheetColumns(groups, count: 1).count == 1)
        #expect(sheetColumns([], count: 3) == [[]])
    }

    @Test func typingNarrowsTheSheet() {
        let groups = [SheetGroup(title: "File", shortcuts: [SheetShortcut(title: "Save", keys: "⌘S"),
                                                             SheetShortcut(title: "Open…", keys: "⌘O")])]
        #expect(filteredSheet(groups, query: "sav").first?.shortcuts.map(\.title) == ["Save"])
        #expect(filteredSheet(groups, query: "zzz").isEmpty)
        #expect(filteredSheet(groups, query: " ") == groups)
    }

    @Test func onlyABareHoldFires() {
        var hold = CommandHold()
        let first = hold.flagsChanged(command: true, others: false)
        #expect(first != nil)
        #expect(hold.shouldFire(first ?? -1))

        // A key in between: ⌘C is being typed.
        hold.interrupted()
        #expect(!hold.shouldFire(first ?? -1))

        // Let go and hold again, then add ⇧: no sheet either.
        _ = hold.flagsChanged(command: false, others: false)
        let second = hold.flagsChanged(command: true, others: false)
        _ = hold.flagsChanged(command: true, others: true)
        #expect(!hold.shouldFire(second ?? -1))
    }

    @Test func lettingGoEndsTheHold() {
        var hold = CommandHold()
        let generation = hold.flagsChanged(command: true, others: false)
        _ = hold.flagsChanged(command: false, others: false)
        #expect(!hold.isHolding)
        #expect(!hold.shouldFire(generation ?? -1))
    }
}

struct ShortcutSheetExtrasTests {
    private let titles = SheetGroupTitles(favourites: "Favourites", mine: "Mine", system: "System")
    private let menus = [
        SheetGroup(title: "File", shortcuts: [SheetShortcut(title: "New", keys: "⌘N"), SheetShortcut(title: "Save", keys: "⌘S")]),
        SheetGroup(title: "Edit", shortcuts: [SheetShortcut(title: "Copy", keys: "⌘C")]),
    ]

    @Test func aDoublePressThatIsHeldFires() {
        var hold = CommandDoubleHold(window: 0.4)
        #expect(hold.flagsChanged(command: true, others: false, at: 0) == nil)
        #expect(hold.flagsChanged(command: false, others: false, at: 0.1) == nil)
        let second = hold.flagsChanged(command: true, others: false, at: 0.3)
        #expect(second != nil)
        #expect(hold.shouldFire(second ?? -1))
        // Letting go ends it.
        _ = hold.flagsChanged(command: false, others: false, at: 2)
        #expect(!hold.shouldFire(second ?? -1))
    }

    @Test func aSlowSecondPressOrAShortcutDoesNotFire() {
        var slow = CommandDoubleHold(window: 0.4)
        _ = slow.flagsChanged(command: true, others: false, at: 0)
        _ = slow.flagsChanged(command: false, others: false, at: 0.1)
        #expect(slow.flagsChanged(command: true, others: false, at: 1) == nil)

        // A long first press is a hold, not a tap.
        var long = CommandDoubleHold(window: 0.4)
        _ = long.flagsChanged(command: true, others: false, at: 0)
        _ = long.flagsChanged(command: false, others: false, at: 0.9)
        #expect(long.flagsChanged(command: true, others: false, at: 1) == nil)

        // ⌘C, then ⌘ again: the key in between cancels the tap.
        var typed = CommandDoubleHold(window: 0.4)
        _ = typed.flagsChanged(command: true, others: false, at: 0)
        typed.interrupted()
        _ = typed.flagsChanged(command: false, others: false, at: 0.1)
        let again = typed.flagsChanged(command: true, others: false, at: 0.2)
        #expect(again == nil)

        // A key during the held second press cancels the wait.
        var held = CommandDoubleHold(window: 0.4)
        _ = held.flagsChanged(command: true, others: false, at: 0)
        _ = held.flagsChanged(command: false, others: false, at: 0.1)
        let second = held.flagsChanged(command: true, others: false, at: 0.2)
        held.interrupted()
        #expect(!held.shouldFire(second ?? -1))
    }

    @Test func favouritesLeadAndHiddenShortcutsLeave() {
        let save = sheetKey(group: "File", shortcut: menus[0].shortcuts[1])
        let copy = sheetKey(group: "Edit", shortcut: menus[1].shortcuts[0])
        let marks = SheetMarks(starred: [save], hidden: [copy])
        let sheet = arrangedSheet(menus, marks: marks, custom: [SheetShortcut(title: "Mine", keys: "⌃T")],
                                  system: [SheetShortcut(title: "Spotlight", keys: "⌘Space")], showHidden: false, titles: titles)
        #expect(sheet.map(\.title) == ["Favourites", "Mine", "File", "System"])
        #expect(sheet[0].shortcuts.map(\.title) == ["Save"])
        // The favourite still knows its menu item.
        #expect(sheet[0].shortcuts[0].origin == save)
        #expect(sheet[1].shortcuts[0].origin == nil)

        let all = arrangedSheet(menus, marks: marks, custom: [], system: [], showHidden: true, titles: titles)
        #expect(all.map(\.title) == ["Favourites", "File", "Edit"])
    }

    @Test func hidingAFavouriteTakesItsStar() {
        var marks = SheetMarks()
        marks.toggleStar("a")
        marks.toggleStar("b")
        #expect(marks.starred == ["a", "b"])
        marks.toggleHidden("a")
        #expect(marks.starred == ["b"])
        #expect(marks.hidden == ["a"])
        marks.toggleHidden("a")
        marks.toggleStar("b")
        #expect(marks.isEmpty)
    }

    @Test func customShortcutsShowInTheirAppOrEverywhere() {
        let all = [
            CustomSheetShortcut(title: "Everywhere", keys: "⌃1"),
            CustomSheetShortcut(title: "Safari only", keys: "⌃2", bundleID: "com.apple.Safari"),
            CustomSheetShortcut(title: "", keys: "⌃3"),
        ]
        #expect(customShortcuts(all, for: "com.apple.Safari").map(\.title) == ["Everywhere", "Safari only"])
        #expect(customShortcuts(all, for: "com.apple.Notes").map(\.title) == ["Everywhere"])
    }

    @Test func theColumnCountFollowsTheChoiceWithinTheScreen() {
        #expect(sheetColumnCount(chosen: 0, screenWidth: 1440, hasShortcuts: true) == 4)
        #expect(sheetColumnCount(chosen: 5, screenWidth: 1440, hasShortcuts: true) == 4)
        #expect(sheetColumnCount(chosen: 2, screenWidth: 1440, hasShortcuts: true) == 2)
        #expect(sheetColumnCount(chosen: 3, screenWidth: 1440, hasShortcuts: false) == 1)
    }

    @Test func settingsFromOlderVersionsStillLoad() throws {
        let data = Data(#"{"columns":3}"#.utf8)
        let settings = StoredSettings.decode(ShortcutSheetSettings.self, from: data, fallback: ShortcutSheetSettings())
        #expect(settings.columns == 3)
        #expect(settings.trigger == .hold)
        #expect(settings.system)
    }
}
