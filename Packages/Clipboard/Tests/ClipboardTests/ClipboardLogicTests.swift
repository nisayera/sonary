import Foundation
import Testing
@testable import Clipboard

struct ClipboardHistoryTests {
    private let t = Date(timeIntervalSince1970: 0)

    @Test func newestFirst() {
        var history = ClipboardHistory()
        history.add("a", at: t)
        history.add("b", at: t)
        #expect(history.entries.map(\.text) == ["b", "a"])
    }

    @Test func duplicateMovesToTop() {
        var history = ClipboardHistory()
        history.add("a", at: t)
        history.add("b", at: t)
        history.add("a", at: t)
        #expect(history.entries.map(\.text) == ["a", "b"])
    }

    @Test func ignoresBlank() {
        var history = ClipboardHistory()
        history.add("   \n", at: t)
        #expect(history.entries.isEmpty)
    }

    @Test func limitDropsOldestUnpinned() {
        var history = ClipboardHistory(limit: 2)
        history.add("old", at: t)
        if let id = history.entries.first?.id { history.togglePin(id) }
        history.add("b", at: t)
        history.add("c", at: t)
        #expect(history.entries.map(\.text) == ["c", "old"])
    }

    @Test func clearKeepsPinned() {
        var history = ClipboardHistory()
        history.add("keep", at: t)
        if let id = history.entries.first?.id { history.togglePin(id) }
        history.add("drop", at: t)
        history.clear()
        #expect(history.entries.map(\.text) == ["keep"])
    }

    @Test func duplicateKeepsPin() {
        var history = ClipboardHistory()
        history.add("a", at: t)
        if let id = history.entries.first?.id { history.togglePin(id) }
        history.add("a", at: t)
        #expect(history.entries.first?.isPinned == true)
    }

    @Test func searchIsCaseInsensitive() {
        var history = ClipboardHistory()
        history.add("Hello World", at: t)
        history.add("other", at: t)
        #expect(history.search("world").map(\.text) == ["Hello World"])
        #expect(history.search("").count == 2)
    }

    @Test func setLimitTrims() {
        var history = ClipboardHistory(limit: 5)
        for i in 0..<5 { history.add("\(i)", at: t) }
        history.setLimit(2)
        #expect(history.entries.count == 2)
    }

    @Test func concealedCopiesAreNotRecorded() {
        #expect(!shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(shouldRecord(types: ["public.utf8-plain-text"]))
    }
}

struct URLCleanerTests {
    @Test func removesUTMAndClickIDs() {
        #expect(cleanedURL("https://example.com/a?utm_source=x&id=5&fbclid=abc") == "https://example.com/a?id=5")
    }

    @Test func dropsEmptyQuery() {
        #expect(cleanedURL("https://example.com/a?utm_medium=mail") == "https://example.com/a")
    }

    @Test func unchangedReturnsNil() {
        #expect(cleanedURL("https://example.com/a?id=5") == nil)
        #expect(cleanedURL("https://example.com/a") == nil)
    }

    @Test func ignoresNonLinksAndText() {
        #expect(cleanedURL("hello world https://x.com/?utm_source=a") == nil)
        #expect(cleanedURL("mailto:a@b.c?utm_source=a") == nil)
    }

    @Test func keepsFragment() {
        #expect(cleanedURL("https://example.com/p?gclid=1#top") == "https://example.com/p#top")
    }
}

struct ClipboardStoreTests {
    @Test func settingsAndHistoryRoundTrip() {
        let defaults = UserDefaults(suiteName: "sonary.clipboardtests.\(UUID().uuidString)")!
        let store = ClipboardStore(defaults: defaults)
        var settings = ClipboardSettings()
        settings.cleanLinks = false
        settings.historyLimit = 80
        store.save(settings)
        #expect(store.loadSettings() == settings)
        var history = ClipboardHistory(limit: 80)
        history.add("x", at: Date(timeIntervalSince1970: 0))
        store.save(history)
        #expect(store.loadHistory(limit: 80).entries.map(\.text) == ["x"])
    }

    @Test func defaultsAreSensible() {
        let settings = ClipboardSettings()
        #expect(settings.cleanLinks)
        #expect(!settings.plainTextPasteShortcut)
        #expect(settings.historyLimit == 50)
    }
}
