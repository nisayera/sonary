import Testing
@testable import Display

struct BrightnessLogicTests {
    @Test func clamps() {
        #expect(clampedBrightness(1.5) == 1)
        #expect(clampedBrightness(-0.3) == 0)
        #expect(clampedBrightness(0.42) == 0.42)
    }

    @Test func stepsUpAndDown() {
        let up = steppedBrightness(0.5, up: true)
        let down = steppedBrightness(0.5, up: false)
        #expect(abs(up - 0.5625) < 0.001)
        #expect(abs(down - 0.4375) < 0.001)
    }

    @Test func stepsStopAtTheEnds() {
        #expect(steppedBrightness(1, up: true) == 1)
        #expect(steppedBrightness(0, up: false) == 0)
    }

    @Test func sixteenStepsCoverTheWholeRange() {
        var value = 0.0
        for _ in 0..<16 { value = steppedBrightness(value, up: true) }
        #expect(value == 1)
    }

    @Test func overlayIsClearAtFullBrightness() {
        #expect(overlayAlpha(for: 1) == 0)
    }

    @Test func overlayNeverGoesFullyBlack() {
        #expect(overlayAlpha(for: 0) == 0.75)
        #expect(overlayAlpha(for: 0, maximumDim: 5) <= 0.95)
    }

    @Test func overlayGrowsAsBrightnessFalls() {
        #expect(overlayAlpha(for: 0.5) > overlayAlpha(for: 0.9))
    }
}
