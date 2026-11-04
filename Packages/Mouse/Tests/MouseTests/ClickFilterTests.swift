import Testing
@testable import Mouse

struct ClickFilterTests {
    private let ms: UInt64 = 1_000_000

    @Test func dropsSecondClickInsideWindow() {
        var filter = ClickFilter(milliseconds: 50)
        let first = filter.shouldDrop(button: 0, timestampNanoseconds: 0)
        let second = filter.shouldDrop(button: 0, timestampNanoseconds: 30 * ms)
        #expect(!first)
        #expect(second)
    }

    @Test func keepsClickAfterWindow() {
        var filter = ClickFilter(milliseconds: 50)
        let first = filter.shouldDrop(button: 0, timestampNanoseconds: 0)
        let second = filter.shouldDrop(button: 0, timestampNanoseconds: 60 * ms)
        #expect(!first)
        #expect(!second)
    }

    @Test func zeroDisablesFilter() {
        var filter = ClickFilter(milliseconds: 0)
        let first = filter.shouldDrop(button: 0, timestampNanoseconds: 0)
        let second = filter.shouldDrop(button: 0, timestampNanoseconds: 1)
        #expect(!first)
        #expect(!second)
    }

    @Test func differentButtonsIndependent() {
        var filter = ClickFilter(milliseconds: 50)
        let first = filter.shouldDrop(button: 0, timestampNanoseconds: 0)
        let other = filter.shouldDrop(button: 1, timestampNanoseconds: 10 * ms)
        #expect(!first)
        #expect(!other)
    }

    @Test func clockGoingBackwardsDoesNotDrop() {
        var filter = ClickFilter(milliseconds: 50)
        let first = filter.shouldDrop(button: 0, timestampNanoseconds: 100 * ms)
        let backwards = filter.shouldDrop(button: 0, timestampNanoseconds: 10 * ms)
        #expect(!first)
        #expect(!backwards)
    }
}

@Suite struct ThreeFingerMiddleClickTests {
    @Test func onlyThreeFingersCount() {
        #expect(shouldBecomeMiddleClick(touchCount: 3, enabled: true))
        #expect(!shouldBecomeMiddleClick(touchCount: 2, enabled: true))
        #expect(!shouldBecomeMiddleClick(touchCount: 4, enabled: true))
        #expect(!shouldBecomeMiddleClick(touchCount: 0, enabled: true), "a mouse carries no touches")
    }

    @Test func offMeansOff() {
        #expect(!shouldBecomeMiddleClick(touchCount: 3, enabled: false))
    }
}
