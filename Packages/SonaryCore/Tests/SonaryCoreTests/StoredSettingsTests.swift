import Foundation
import Testing
@testable import SonaryCore

private enum SampleMode: String, Codable, Equatable {
    case one, two
}

private enum SampleAction: Codable, Equatable {
    case none
    case key(code: Int)
}

private struct SampleItem: Codable, Equatable {
    var title: String
    var count: Int
}

private struct SampleInner: Codable, Equatable {
    var name = "inner"
    var size = 3
}

/// A settings struct as a later version would have it, with fields the stored data predates.
private struct SampleSettings: Codable, Equatable {
    var enabled = false
    var limit = 10
    var mode = SampleMode.one
    var action = SampleAction.none
    var items: [SampleItem] = []
    var inner = SampleInner()
    var note: String?
    var byApp: [String: Int] = [:]
}

private func json(_ text: String) -> Data { Data(text.utf8) }

struct StoredSettingsTests {
    @Test func readsCompleteDataAsItIs() throws {
        var settings = SampleSettings()
        settings.enabled = true
        settings.items = [SampleItem(title: "a", count: 1)]
        settings.action = .key(code: 12)
        let data = try JSONEncoder().encode(settings)
        #expect(StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings()) == settings)
    }

    @Test func aNewFieldTakesItsDefaultAndTheRestSurvives() {
        // Saved by an older version: no "limit", no "inner", no "byApp".
        let data = json(#"{"enabled": true, "mode": "two", "action": {"key": {"code": 7}}, "items": [{"title": "x", "count": 2}]}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.enabled)
        #expect(settings.mode == .two)
        #expect(settings.action == .key(code: 7))
        #expect(settings.items == [SampleItem(title: "x", count: 2)])
        #expect(settings.limit == 10)
        #expect(settings.inner == SampleInner())
    }

    @Test func aNewNestedFieldTakesItsDefault() {
        let data = json(#"{"enabled": true, "limit": 4, "mode": "one", "action": {"none": {}}, "items": [], "inner": {"name": "kept"}, "byApp": {}}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.inner.name == "kept")
        #expect(settings.inner.size == 3)
        #expect(settings.limit == 4)
    }

    @Test func aRemovedEnumCaseResetsOnlyThatField() {
        let data = json(#"{"enabled": true, "limit": 5, "mode": "three", "action": {"none": {}}, "items": [], "inner": {"name": "a", "size": 1}, "byApp": {}}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.mode == .one)
        #expect(settings.enabled)
        #expect(settings.limit == 5)
        #expect(settings.inner == SampleInner(name: "a", size: 1))
    }

    @Test func anUnreadableListElementIsDroppedTheOthersStay() {
        let data = json(#"{"enabled": false, "limit": 1, "mode": "one", "action": {"none": {}}, "items": [{"title": "a", "count": 1}, {"title": "b"}, {"title": "c", "count": 3}], "inner": {"name": "a", "size": 1}, "byApp": {}}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.items == [SampleItem(title: "a", count: 1), SampleItem(title: "c", count: 3)])
    }

    @Test func anUnreadableDictionaryEntryIsDroppedTheOthersStay() {
        let data = json(#"{"com.a": 1, "com.b": "oops", "com.c": 3}"#)
        let values = StoredSettings.decode([String: Int].self, from: data, fallback: [:])
        #expect(values == ["com.a": 1, "com.c": 3])
    }

    @Test func dictionaryEntriesSurviveANewField() {
        let data = json(#"{"enabled": true, "byApp": {"com.a": 2}}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.byApp == ["com.a": 2])
        #expect(settings.enabled)
    }

    @Test func aBrokenOptionalFieldBecomesNil() {
        let data = json(#"{"enabled": true, "limit": 2, "mode": "one", "action": {"none": {}}, "items": [], "inner": {"name": "a", "size": 1}, "note": 42, "byApp": {}}"#)
        let settings = StoredSettings.decode(SampleSettings.self, from: data, fallback: SampleSettings())
        #expect(settings.note == nil)
        #expect(settings.limit == 2)
    }

    @Test func garbageGivesTheFallback() {
        var fallback = SampleSettings()
        fallback.limit = 99
        #expect(StoredSettings.decode(SampleSettings.self, from: json("not json"), fallback: fallback) == fallback)
        #expect(StoredSettings.decode(SampleSettings.self, from: json("[1, 2]"), fallback: fallback) == fallback)
    }

    @Test func loadsAndSavesThroughUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "sonary.storedsettings.\(UUID().uuidString)"))
        #expect(StoredSettings.load(SampleSettings.self, key: "s", from: defaults, fallback: SampleSettings()) == SampleSettings())
        var settings = SampleSettings()
        settings.items = [SampleItem(title: "kept", count: 1)]
        StoredSettings.save(settings, key: "s", to: defaults)
        #expect(StoredSettings.load(SampleSettings.self, key: "s", from: defaults, fallback: SampleSettings()) == settings)
    }
}
