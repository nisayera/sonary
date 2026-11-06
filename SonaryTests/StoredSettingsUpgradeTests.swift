import Clipboard
import Foundation
import Mouse
import SonaryCore
import Testing
import Tools

/// Settings as an older version saved them, without the fields added since. Before
/// `StoredSettings` any of these reset the whole module to its defaults.
struct StoredSettingsUpgradeTests {
    @Test func toolsKeepTheScratchpadAndSnippets() {
        let old = Data(#"""
        {"shortcuts": false, "scratchpad": "my notes",
         "snippets": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "title": "Sig", "text": "Best, L."}]}
        """#.utf8)
        let settings = StoredSettings.decode(ToolsSettings.self, from: old, fallback: ToolsSettings())
        #expect(settings.scratchpad == "my notes")
        #expect(settings.snippets.map(\.text) == ["Best, L."])
        #expect(settings.shortcuts == false)
    }

    @Test func mouseKeepsItsScrolling() {
        let old = Data(#"""
        {"linearScroll": true, "scrollLinesPerStep": 5, "smoothScroll": false, "smoothness": 0.5,
         "reverseScroll": true, "disableAcceleration": false, "buttonMappings": [],
         "clickFilterMilliseconds": 0, "appOverrides": {}}
        """#.utf8)
        let settings = StoredSettings.decode(MouseSettings.self, from: old, fallback: MouseSettings())
        #expect(settings.linearScroll)
        #expect(settings.scrollLinesPerStep == 5)
        #expect(settings.reverseScroll)
    }

    @Test func clipboardHistoryKeepsWhatItCanRead() {
        // The second entry has a kind of content this version does not know.
        let old = Data(#"""
        {"limit": 50, "entries": [
          {"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "content": {"text": {"_0": "hello"}},
           "copiedAt": 700000000, "isPinned": true},
          {"id": "7F9619FF-8B86-D011-B42D-00CF4FC964FF", "content": {"rtf": {"_0": "x"}},
           "copiedAt": 700000001, "isPinned": false}]}
        """#.utf8)
        let history = StoredSettings.decode(ClipboardHistory.self, from: old, fallback: ClipboardHistory(limit: 50))
        #expect(history.entries.map(\.text) == ["hello"])
        #expect(history.entries.first?.isPinned == true)
    }
}
