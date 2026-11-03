import Testing
@testable import Mouse

struct ClickFilterTests {
    private let ms: UInt64 = 1_000_000

    @Test func dropsSecondClickInsideWindow() {
        var filter = ClickFilter(milliseconds: 50)
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 0))
        #expect(filter.shouldDrop(button: 0, timestampNanoseconds: 30 * ms))
    }

    @Test func keepsClickAfterWindow() {
        var filter = ClickFilter(milliseconds: 50)
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 0))
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 60 * ms))
    }

    @Test func zeroDisablesFilter() {
        var filter = ClickFilter(milliseconds: 0)
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 0))
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 1))
    }

    @Test func differentButtonsIndependent() {
        var filter = ClickFilter(milliseconds: 50)
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 0))
        #expect(!filter.shouldDrop(button: 1, timestampNanoseconds: 10 * ms))
    }

    @Test func clockGoingBackwardsDoesNotDrop() {
        var filter = ClickFilter(milliseconds: 50)
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 100 * ms))
        #expect(!filter.shouldDrop(button: 0, timestampNanoseconds: 10 * ms))
    }
}
