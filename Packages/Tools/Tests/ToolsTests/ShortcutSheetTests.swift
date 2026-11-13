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
