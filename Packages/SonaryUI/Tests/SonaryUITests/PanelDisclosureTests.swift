import Testing
@testable import SonaryUI

struct PanelDisclosureTests {
    @Test func openingOneSectionLeavesTheOthersOpen() {
        let stored = panelTogglingSection("media", open: true, in: "capture")
        #expect(panelOpenSections(stored) == ["capture", "media"])
    }

    @Test func closingOneSectionLeavesTheOthersOpen() {
        let stored = panelTogglingSection("capture", open: false, in: "capture,media")
        #expect(panelOpenSections(stored) == ["media"])
    }

    @Test func aSingleStoredSectionFromBeforeStillReads() {
        #expect(panelOpenSections("usage") == ["usage"])
        #expect(panelOpenSections("").isEmpty)
        #expect(panelOpenSections(panelTogglingSection("usage", open: true, in: "usage")) == ["usage"])
    }
}
