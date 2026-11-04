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

@Suite struct GestureTests {
    private let mappings = [
        GestureMapping(button: 3, direction: .up, action: .missionControl),
        GestureMapping(button: 3, direction: .left, action: .back),
    ]

    @Test func theLongerAxisDecides() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(gestureDirection(from: origin, to: CGPoint(x: 100, y: 140)) == .up)
        #expect(gestureDirection(from: origin, to: CGPoint(x: 100, y: 60)) == .down)
        #expect(gestureDirection(from: origin, to: CGPoint(x: 140, y: 110)) == .right)
        #expect(gestureDirection(from: origin, to: CGPoint(x: 60, y: 110)) == .left)
    }

    @Test func aSmallWobbleIsNoGesture() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(gestureDirection(from: origin, to: CGPoint(x: 110, y: 110)) == nil)
        #expect(gestureDirection(from: origin, to: origin) == nil)
    }

    @Test func gesturesOnlyApplyToExtraButtons() {
        #expect(action(forGesture: 3, direction: .up, in: mappings) == .missionControl)
        #expect(action(forGesture: 3, direction: .down, in: mappings) == nil, "nothing set for that way")
        #expect(action(forGesture: 0, direction: .up, in: [GestureMapping(button: 0, direction: .up, action: .back)]) == nil,
                "the left button is never taken over")
    }

    @Test func knowsWhichButtonsHaveGestures() {
        #expect(hasGestures(button: 3, in: mappings))
        #expect(!hasGestures(button: 4, in: mappings))
    }

    @Test func theSideWheelKnowsItsWay() {
        #expect(sideWheelDirection(deltaX: 3) == .right)
        #expect(sideWheelDirection(deltaX: -3) == .left)
        #expect(sideWheelDirection(deltaX: 0) == nil)
    }
}

@Suite struct GestureProcessingTests {
    private func processor() -> EventProcessor {
        var settings = MouseSettings()
        settings.buttonMappings = [ButtonMapping(button: 3, action: .forward)]
        settings.gestureMappings = [GestureMapping(button: 3, direction: .up, action: .missionControl)]
        return EventProcessor(settings: settings)
    }

    @Test func aButtonWithGesturesWaitsForTheRelease() {
        var subject = processor()
        let down = subject.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil)
        #expect(down == .swallow, "the click is held until the push is known")
    }

    @Test func aPushRunsTheGesture() {
        var subject = processor()
        _ = subject.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil)
        let up = subject.process(.buttonUp(button: 3, direction: .up), bundleID: nil)
        #expect(up == .perform(.missionControl))
    }

    @Test func aClickWithoutAPushStillDoesTheButtonsOwnJob() {
        var subject = processor()
        _ = subject.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil)
        let up = subject.process(.buttonUp(button: 3, direction: nil), bundleID: nil)
        #expect(up == .perform(.forward))
    }

    @Test func aButtonWithoutGesturesIsUntouched() {
        var subject = processor()
        let up = subject.process(.buttonUp(button: 4, direction: .up), bundleID: nil)
        #expect(up == .passThrough)
    }

    @Test func theSideWheelRunsItsActionInsteadOfScrolling() {
        var settings = MouseSettings()
        settings.sideWheelRight = .forward
        var subject = EventProcessor(settings: settings)
        let turned = subject.process(.scroll(ScrollSample(deltaY: 0, deltaX: 2)), bundleID: nil)
        #expect(turned == .perform(.forward))
        let other = subject.process(.scroll(ScrollSample(deltaY: 0, deltaX: -2)), bundleID: nil)
        #expect(other == .passThrough, "nothing is set for the other way")
    }
}
