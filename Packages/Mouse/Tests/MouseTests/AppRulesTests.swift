import Testing
@testable import Mouse

struct AppRulesTests {
    private func base() -> MouseSettings {
        var settings = MouseSettings()
        settings.linearScroll = true
        settings.reverseScroll = true
        settings.clickFilterMilliseconds = 40
        settings.buttonMappings = [ButtonMapping(button: 3, action: .back)]
        settings.appOverrides = [
            "com.example.off": AppOverride(disabled: true),
            "com.example.noreverse": AppOverride(reverseScroll: false),
        ]
        return settings
    }

    @Test func nilBundleUsesBase() {
        #expect(effectiveSettings(base(), bundleID: nil) == base())
    }

    @Test func unknownBundleUsesBase() {
        #expect(effectiveSettings(base(), bundleID: "com.other") == base())
    }

    @Test func overrideReplacesField() {
        let result = effectiveSettings(base(), bundleID: "com.example.noreverse")
        #expect(!result.reverseScroll)
        #expect(result.linearScroll)
    }

    @Test func disabledTurnsEverythingOff() {
        let result = effectiveSettings(base(), bundleID: "com.example.off")
        #expect(!result.linearScroll && !result.reverseScroll && !result.smoothScroll)
        #expect(result.buttonMappings.isEmpty && result.clickFilterMilliseconds == 0)
    }
}
