import Foundation
import Testing
@testable import Clipboard

struct ClipboardHistoryTests {
    private let t = Date(timeIntervalSince1970: 0)

    @Test func newestFirst() {
        var history = ClipboardHistory()
        history.add("a", at: t)
        history.add("b", at: t)
        #expect(history.entries.map(\.searchText) == ["b", "a"])
    }

    @Test func duplicateMovesToTop() {
        var history = ClipboardHistory()
        history.add("a", at: t)
        history.add("b", at: t)
        history.add("a", at: t)
        #expect(history.entries.map(\.searchText) == ["a", "b"])
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
        #expect(history.entries.map(\.searchText) == ["c", "old"])
    }

    @Test func clearKeepsPinned() {
        var history = ClipboardHistory()
        history.add("keep", at: t)
        if let id = history.entries.first?.id { history.togglePin(id) }
        history.add("drop", at: t)
        history.clear()
        #expect(history.entries.map(\.searchText) == ["keep"])
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
        #expect(history.search("world").map(\.searchText) == ["Hello World"])
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
        #expect(store.loadHistory(limit: 80).entries.map(\.searchText) == ["x"])
    }

    @Test func defaultsAreSensible() {
        let settings = ClipboardSettings()
        #expect(settings.cleanLinks)
        #expect(!settings.plainTextPasteShortcut)
        #expect(settings.historyLimit == 50)
    }
}

struct ClipboardContentTests {
    private let t = Date(timeIntervalSince1970: 1_000)

    @Test func imagesAndFilesAreKept() {
        var history = ClipboardHistory()
        history.add(.image(fileName: "a.png"), at: t)
        history.add(.files(["/tmp/report.pdf", "/tmp/notes.txt"]), at: t)
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.searchText == "report.pdf, notes.txt")
        #expect(history.entries.last?.searchText == "Image")
        #expect(history.entries.last?.text == nil)
    }

    @Test func emptyFileListIsIgnored() {
        var history = ClipboardHistory()
        history.add(.files([]), at: t)
        #expect(history.entries.isEmpty)
    }

    @Test func copyingTheSameImageAgainMovesItUp() {
        var history = ClipboardHistory()
        history.add(.image(fileName: "a.png"), at: t)
        history.add("text", at: t)
        history.add(.image(fileName: "a.png"), at: t)
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.content == .image(fileName: "a.png"))
    }

    @Test func searchFindsFileNames() {
        var history = ClipboardHistory()
        history.add(.files(["/tmp/invoice-2026.pdf"]), at: t)
        #expect(history.search("invoice").count == 1)
        #expect(history.search("nothing").isEmpty)
    }
}

struct ClipboardAutoClearTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func dropsOldUnpinnedEntries() {
        var history = ClipboardHistory()
        history.add("old", at: now.addingTimeInterval(-3600))
        history.add("fresh", at: now.addingTimeInterval(-60))
        let dropped = history.autoClear(now: now, olderThanMinutes: 15)
        #expect(dropped.map(\.searchText) == ["old"])
        #expect(history.entries.map(\.searchText) == ["fresh"])
    }

    @Test func keepsPinnedEntries() {
        var history = ClipboardHistory()
        history.add("old", at: now.addingTimeInterval(-3600))
        if let id = history.entries.first?.id { history.togglePin(id) }
        #expect(history.autoClear(now: now, olderThanMinutes: 15).isEmpty)
        #expect(history.entries.count == 1)
    }

    @Test func zeroMinutesKeepsEverything() {
        var history = ClipboardHistory()
        history.add("old", at: now.addingTimeInterval(-99_999))
        #expect(history.autoClear(now: now, olderThanMinutes: 0).isEmpty)
        #expect(history.entries.count == 1)
    }

    @Test func orphanedImageFilesAreReported() {
        var history = ClipboardHistory()
        history.add(.image(fileName: "keep.png"), at: now)
        #expect(history.orphanedImageFiles(knownFiles: ["keep.png", "gone.png"]) == ["gone.png"])
    }

    @Test func newDefaultsKeepEverythingUntilAsked() {
        let settings = ClipboardSettings()
        #expect(settings.autoClearMinutes == 0)
        #expect(!settings.clearOnSleep && !settings.clearOnLock)
        #expect(settings.captureImages && settings.captureFiles)
    }
}

@Suite struct FinderHelperTests {
    @Test func picksAFreeName() {
        #expect(uniqueFileName(base: "Shot", extension: "png") { _ in false } == "Shot.png")
        let taken = ["Shot.png", "Shot 2.png"]
        #expect(uniqueFileName(base: "Shot", extension: "png") { taken.contains($0) } == "Shot 3.png")
    }

    @Test func stampsTheImageName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5, second: 4))!
        let name = clipboardImageName(now: date, calendar: calendar)
        #expect(name.hasPrefix("Clipboard 2026-03-07 at "))
        #expect(!name.contains("/"))
    }
}
