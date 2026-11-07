import Testing
@testable import SonaryCore

struct PanelTabOrderTests {
    @Test func placedTabsComeFirstAndTheRestKeepTheirOrder() {
        let tabs = orderedPanelTabs(available: ["monitor", "sound", "tools", "apps"], order: ["tools", "gone", "monitor"],
                                    hidden: [])
        #expect(tabs == ["tools", "monitor", "sound", "apps"])
    }

    @Test func hiddenTabsAreLeftOut() {
        #expect(orderedPanelTabs(available: ["monitor", "sound"], order: [], hidden: ["sound"]) == ["monitor"])
    }
}

struct OptionSearchTests {
    @Test func onlyRealOptionTextsAreSearched() {
        let table = [
            "a": "Linear scrolling", "b": "On", "c": "Copied %@", "d": "Turn off pointer acceleration",
            "e": String(repeating: "word ", count: 40), "f": "Turn off pointer acceleration",
        ]
        #expect(searchableTexts(table) == ["Linear scrolling", "Turn off pointer acceleration"])
    }
}
