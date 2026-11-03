import Foundation
import Testing
@testable import Mouse

struct MouseSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sonary.mousetests.\(UUID().uuidString)")!
    }

    @Test func roundTripsThroughStore() {
        let store = MouseSettingsStore(defaults: makeDefaults())
        var settings = MouseSettings()
        settings.linearScroll = true
        settings.scrollLinesPerStep = 5
        settings.buttonMappings = [ButtonMapping(button: 3, action: .back)]
        settings.appOverrides = ["com.example.app": AppOverride(disabled: true)]
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func corruptDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "mouse.settings")
        #expect(MouseSettingsStore(defaults: defaults).load() == MouseSettings())
    }

    @Test func defaultsAreSafe() {
        let settings = MouseSettings()
        #expect(!settings.linearScroll && !settings.smoothScroll && !settings.reverseScroll)
        #expect(!settings.disableAcceleration)
        #expect(settings.scrollLinesPerStep == 3)
        #expect(settings.clickFilterMilliseconds == 0)
        #expect(settings.buttonMappings.isEmpty && settings.appOverrides.isEmpty)
    }
}
