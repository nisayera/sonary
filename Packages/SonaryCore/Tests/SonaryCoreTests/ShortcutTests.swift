import Foundation
import Testing
@testable import SonaryCore

struct ShortcutLogicTests {
    @Test func readsCombinationsTheWayTheKeyboardIsPrinted() {
        let combo = KeyCombo(keyCode: 17, modifiers: KeyModifier.control | KeyModifier.option)
        #expect(shortcutDisplay(combo) == "⌃⌥T")
        let all = KeyCombo(keyCode: 49, modifiers: KeyModifier.command | KeyModifier.shift
            | KeyModifier.option | KeyModifier.control)
        #expect(shortcutDisplay(all) == "⌃⌥⇧⌘Space")
        #expect(shortcutDisplay(.none).isEmpty)
    }

    @Test func namesTheKeysAPersonSees() {
        #expect(keyName(36) == "↩")
        #expect(keyName(126) == "↑")
        #expect(keyName(0) == "A")
        #expect(keyName(29) == "0")
        #expect(keyName(999) == "#999")
    }

    @Test func aShortcutWithoutModifiersIsNotUsable() {
        #expect(!KeyCombo(keyCode: 17, modifiers: 0).isUsable)
        #expect(KeyCombo(keyCode: 17, modifiers: KeyModifier.control).isUsable)
        #expect(!KeyCombo.none.isUsable)
        #expect(KeyCombo.none.isEmpty)
    }

    @Test func refusesAPlainKeyAndAClash() {
        let taken = ["a": KeyCombo(keyCode: 17, modifiers: KeyModifier.control)]
        let titles = ["a": "Copy text from screen"]
        #expect(shortcutProblem(KeyCombo(keyCode: 17, modifiers: 0), for: "b",
                                taken: taken, titles: titles) == .needsModifier)
        #expect(shortcutProblem(KeyCombo(keyCode: 17, modifiers: KeyModifier.control), for: "b",
                                taken: taken, titles: titles) == .takenBy("Copy text from screen"))
        // Its own combination is not a clash with itself.
        #expect(shortcutProblem(KeyCombo(keyCode: 17, modifiers: KeyModifier.control), for: "a",
                                taken: taken, titles: titles) == nil)
        // Switching a shortcut off is always allowed.
        #expect(shortcutProblem(.none, for: "b", taken: taken, titles: titles) == nil)
        #expect(shortcutProblem(KeyCombo(keyCode: 18, modifiers: KeyModifier.control), for: "b",
                                taken: taken, titles: titles) == nil)
    }

    @MainActor
    @Test func keepsWhatTheUserSetAndGivesTheDefaultBack() {
        let defaults = UserDefaults(suiteName: "app.sonary.tests.shortcuts.\(UUID().uuidString)")!
        let store = ShortcutStore(defaults: defaults)
        let shipped = KeyCombo(keyCode: 17, modifiers: KeyModifier.control)
        store.describe([ShortcutDefinition(id: "x", title: "X", group: "G", defaultCombo: shipped)])
        #expect(store.combo(for: "x") == shipped)
        #expect(!store.isCustom("x"))

        let mine = KeyCombo(keyCode: 18, modifiers: KeyModifier.command)
        store.set(mine, for: "x")
        #expect(store.combo(for: "x") == mine)
        #expect(store.isCustom("x"))
        #expect(ShortcutStore(defaults: defaults).combo(for: "x") == .none,
                "an unknown id has no default to fall back to")

        store.set(nil, for: "x")
        #expect(store.combo(for: "x") == shipped)
        #expect(!store.isCustom("x"))
    }

    @MainActor
    @Test func describingTwiceReplacesRatherThanDuplicates() {
        let defaults = UserDefaults(suiteName: "app.sonary.tests.shortcuts.\(UUID().uuidString)")!
        let store = ShortcutStore(defaults: defaults)
        let first = ShortcutDefinition(id: "x", title: "X", group: "G", defaultCombo: .none)
        store.describe([first])
        store.describe([ShortcutDefinition(id: "x", title: "X2", group: "G", defaultCombo: .none)])
        #expect(store.definitions.count == 1)
        #expect(store.definitions[0].title == "X2")
        #expect(store.inUse.isEmpty, "a shortcut that is switched off holds nothing")
    }
}
