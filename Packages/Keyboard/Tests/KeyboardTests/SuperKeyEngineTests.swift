import Testing
@testable import Keyboard

struct SuperKeyEngineTests {
    @Test func quickTapRunsTheTapAction() {
        var engine = SuperKeyEngine(tapTimeout: 0.5)
        let press = engine.sourcePressed(at: 10)
        let release = engine.sourceReleased(at: 10.2)
        #expect(press == .swallow)
        #expect(release == .tap)
    }

    @Test func longPressAloneDoesNothing() {
        var engine = SuperKeyEngine(tapTimeout: 0.5)
        _ = engine.sourcePressed(at: 10)
        #expect(engine.sourceReleased(at: 11) == .swallow)
    }

    @Test func otherKeyWhileHeldBecomesHyper() {
        var engine = SuperKeyEngine()
        _ = engine.sourcePressed(at: 10)
        #expect(engine.otherKeyPressed() == .hyper)
    }

    @Test func usingItAsModifierCancelsTheTap() {
        var engine = SuperKeyEngine(tapTimeout: 0.5)
        _ = engine.sourcePressed(at: 10)
        _ = engine.otherKeyPressed()
        #expect(engine.sourceReleased(at: 10.1) == .swallow)
    }

    @Test func otherKeysPassWhenNotHolding() {
        var engine = SuperKeyEngine()
        #expect(engine.otherKeyPressed() == .pass)
    }

    @Test func resetStopsHolding() {
        var engine = SuperKeyEngine()
        _ = engine.sourcePressed(at: 10)
        engine.reset()
        #expect(!engine.isHolding)
        #expect(engine.otherKeyPressed() == .pass)
    }

    @Test func clockGoingBackwardsIsNotATap() {
        var engine = SuperKeyEngine(tapTimeout: 0.5)
        _ = engine.sourcePressed(at: 10)
        #expect(engine.sourceReleased(at: 9) == .swallow)
    }

    @Test func sourcesHaveDistinctKeyCodes() {
        let codes = SuperKeySource.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func exclusionsTurnItOff() {
        var settings = KeyboardSettings()
        settings.superKeyEnabled = true
        settings.excludedApps = ["com.example.game"]
        #expect(superKeyActive(settings, bundleID: nil))
        #expect(superKeyActive(settings, bundleID: "com.other"))
        #expect(!superKeyActive(settings, bundleID: "com.example.game"))
        settings.superKeyEnabled = false
        #expect(!superKeyActive(settings, bundleID: "com.other"))
    }
}

struct KeyDebouncerTests {
    private let ms: UInt64 = 1_000_000

    @Test func dropsTheSecondPressInsideTheWindow() {
        var debouncer = KeyDebouncer(milliseconds: 40)
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 0))
        #expect(debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 20 * ms))
    }

    @Test func keepsNormalTyping() {
        var debouncer = KeyDebouncer(milliseconds: 40)
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 0))
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 90 * ms))
    }

    @Test func otherKeysAreUnaffected() {
        var debouncer = KeyDebouncer(milliseconds: 40)
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 0))
        #expect(!debouncer.shouldDrop(keyCode: 5, timestampNanoseconds: 1 * ms))
    }

    @Test func zeroTurnsItOff() {
        var debouncer = KeyDebouncer(milliseconds: 0)
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 0))
        #expect(!debouncer.shouldDrop(keyCode: 4, timestampNanoseconds: 1))
    }

    @Test func debounceIsOffByDefault() {
        #expect(KeyboardSettings().debounceMilliseconds == 0)
    }
}
