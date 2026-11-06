import CoreGraphics
import Testing
@testable import Mouse

struct ScrollMathTests {
    @Test func wheelDetection() {
        #expect(isWheelEvent(ScrollSample(deltaY: 1)))
        #expect(!isWheelEvent(ScrollSample(deltaY: 1, isContinuous: true)))
        #expect(!isWheelEvent(ScrollSample(deltaY: 1, scrollPhase: 4)))
        #expect(!isWheelEvent(ScrollSample(deltaY: 1, momentumPhase: 2)))
    }

    @Test func linearStepIsConstant() {
        #expect(linearized(ScrollSample(deltaY: 1), linesPerStep: 3).deltaY == 3)
        #expect(linearized(ScrollSample(deltaY: 7), linesPerStep: 3).deltaY == 3)
    }

    @Test func linearKeepsSign() {
        #expect(linearized(ScrollSample(deltaY: -2), linesPerStep: 3).deltaY == -3)
        #expect(linearized(ScrollSample(deltaY: 0, deltaX: -1), linesPerStep: 2).deltaX == -2)
    }

    @Test func trackpadUnchangedByLinear() {
        let trackpad = ScrollSample(deltaY: 7.5, isContinuous: true, scrollPhase: 2)
        #expect(linearized(trackpad, linesPerStep: 3) == trackpad)
    }

    @Test func reverseFlipsWheelOnly() {
        let wheel = ScrollSample(deltaY: 2, deltaX: -1)
        let flipped = reversed(wheel)
        #expect(flipped.deltaY == -2 && flipped.deltaX == 1)
        let trackpad = ScrollSample(deltaY: 2, isContinuous: true)
        #expect(reversed(trackpad) == trackpad)
    }

    @Test func zeroDeltaStaysZero() {
        let result = linearized(ScrollSample(deltaY: 0), linesPerStep: 3)
        #expect(result.deltaY == 0 && result.deltaX == 0)
        #expect(reversed(ScrollSample(deltaY: 0)).deltaY == 0)
    }
}

struct HorizontalScrollTests {
    @Test func holdingTheKeyTurnsTheWheelSideways() {
        let sample = ScrollSample(deltaY: 3, modifiers: .shift)
        let result = horizontalized(sample, whileHolding: .shift)
        #expect(result.deltaX == 3 && result.deltaY == 0)
    }

    @Test func withoutTheKeyNothingChanges() {
        let sample = ScrollSample(deltaY: 3)
        #expect(horizontalized(sample, whileHolding: .shift) == sample)
    }

    @Test func turnedOffNothingChanges() {
        let sample = ScrollSample(deltaY: 3, modifiers: .shift)
        #expect(horizontalized(sample, whileHolding: .none) == sample)
    }

    @Test func trackpadsAreLeftAlone() {
        let trackpad = ScrollSample(deltaY: 3, isContinuous: true, modifiers: .option)
        #expect(horizontalized(trackpad, whileHolding: .option) == trackpad)
    }

    @Test func anotherKeyDoesNotCount() {
        let sample = ScrollSample(deltaY: 3, modifiers: .command)
        #expect(horizontalized(sample, whileHolding: .option) == sample)
    }

    @Test func eachAxisReversesOnItsOwn() {
        let wheel = ScrollSample(deltaY: 2, deltaX: -1)
        let vertical = reversed(wheel, vertical: true, horizontal: false)
        #expect(vertical.deltaY == -2 && vertical.deltaX == -1)
        let sideways = reversed(wheel, vertical: false, horizontal: true)
        #expect(sideways.deltaY == 2 && sideways.deltaX == 1)
        #expect(reversed(wheel, vertical: false, horizontal: false) == wheel)
    }

    @Test func holdingTheZoomKeyTurnsTheWheelIntoZoom() {
        let command = UInt64(CGEventFlags.maskCommand.rawValue)
        let up = ScrollSample(deltaY: 1, modifiers: .option)
        #expect(zoomAction(for: up, whileHolding: .option) == .keyboardShortcut(keyCode: 24, modifiers: command))
        let down = ScrollSample(deltaY: -1, modifiers: .option)
        #expect(zoomAction(for: down, whileHolding: .option) == .keyboardShortcut(keyCode: 27, modifiers: command))
        #expect(zoomAction(for: ScrollSample(deltaY: 1), whileHolding: .option) == nil)
        #expect(zoomAction(for: up, whileHolding: .none) == nil)
        let trackpad = ScrollSample(deltaY: 1, isContinuous: true, modifiers: .option)
        #expect(zoomAction(for: trackpad, whileHolding: .option) == nil)
    }
}
