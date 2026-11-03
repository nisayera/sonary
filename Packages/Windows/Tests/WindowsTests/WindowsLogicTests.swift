import CoreGraphics
import Testing
@testable import Windows

struct WindowLayoutTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let current = CGRect(x: 10, y: 10, width: 400, height: 300)

    @Test func halves() {
        #expect(layoutFrame(.leftHalf, visible: visible, current: current) == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(layoutFrame(.rightHalf, visible: visible, current: current) == CGRect(x: 500, y: 0, width: 500, height: 800))
        #expect(layoutFrame(.topHalf, visible: visible, current: current) == CGRect(x: 0, y: 400, width: 1000, height: 400))
    }

    @Test func quartersAndThirds() {
        #expect(layoutFrame(.topRight, visible: visible, current: current) == CGRect(x: 500, y: 400, width: 500, height: 400))
        #expect(layoutFrame(.centerThird, visible: CGRect(x: 0, y: 0, width: 900, height: 600), current: current)
            == CGRect(x: 300, y: 0, width: 300, height: 600))
    }

    @Test func maximizeFillsVisibleFrame() {
        let v = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        #expect(layoutFrame(.maximize, visible: v, current: current) == v)
    }

    @Test func centerKeepsSizeAndClamps() {
        #expect(layoutFrame(.center, visible: visible, current: current) == CGRect(x: 300, y: 250, width: 400, height: 300))
        let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        #expect(layoutFrame(.center, visible: visible, current: huge) == visible)
    }

    @Test func respectsScreenOffset() {
        let v = CGRect(x: 1920, y: 0, width: 1000, height: 800)
        #expect(layoutFrame(.leftHalf, visible: v, current: current).minX == 1920)
    }

    @Test func axConversionRoundTrips() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = axRect(fromCocoa: cocoa, primaryScreenHeight: 1000)
        #expect(ax == CGRect(x: 100, y: 400, width: 300, height: 400))
        #expect(cocoaRect(fromAX: ax, primaryScreenHeight: 1000) == cocoa)
    }

    @Test func everyActionHasADistinctKey() {
        let codes = LayoutAction.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }
}

struct QuitGuardTests {
    @Test func firstPressIsSwallowed() {
        var guardian = QuitGuard()
        #expect(!guardian.shouldQuit(app: "a", at: 10))
    }

    @Test func secondPressInsideWindowQuits() {
        var guardian = QuitGuard(window: 1.5)
        _ = guardian.shouldQuit(app: "a", at: 10)
        #expect(guardian.shouldQuit(app: "a", at: 11))
    }

    @Test func slowSecondPressStartsOver() {
        var guardian = QuitGuard(window: 1.5)
        _ = guardian.shouldQuit(app: "a", at: 10)
        #expect(!guardian.shouldQuit(app: "a", at: 13))
        #expect(guardian.shouldQuit(app: "a", at: 13.5))
    }

    @Test func otherAppStartsOver() {
        var guardian = QuitGuard()
        _ = guardian.shouldQuit(app: "a", at: 10)
        #expect(!guardian.shouldQuit(app: "b", at: 10.5))
    }
}
