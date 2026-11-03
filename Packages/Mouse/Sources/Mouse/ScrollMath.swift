import Foundation

/// The parts of a scroll event the mouse module cares about.
public struct ScrollSample: Equatable, Sendable {
    public var deltaY: Double
    public var deltaX: Double
    public var isContinuous: Bool
    public var scrollPhase: Int
    public var momentumPhase: Int

    public init(deltaY: Double, deltaX: Double = 0, isContinuous: Bool = false, scrollPhase: Int = 0, momentumPhase: Int = 0) {
        self.deltaY = deltaY
        self.deltaX = deltaX
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
    }
}

/// True only for events from a classic scroll wheel (not trackpads or Magic Mouse).
public func isWheelEvent(_ sample: ScrollSample) -> Bool {
    !sample.isContinuous && sample.scrollPhase == 0 && sample.momentumPhase == 0
}

private func normalized(_ value: Double, linesPerStep: Int) -> Double {
    if value > 0 { return Double(linesPerStep) }
    if value < 0 { return -Double(linesPerStep) }
    return 0
}

/// Makes every wheel notch scroll the same number of lines, independent of wheel acceleration.
public func linearized(_ sample: ScrollSample, linesPerStep: Int) -> ScrollSample {
    guard isWheelEvent(sample) else { return sample }
    var result = sample
    result.deltaY = normalized(sample.deltaY, linesPerStep: linesPerStep)
    result.deltaX = normalized(sample.deltaX, linesPerStep: linesPerStep)
    return result
}

/// Reverses the scroll direction of wheel events only.
public func reversed(_ sample: ScrollSample) -> ScrollSample {
    guard isWheelEvent(sample) else { return sample }
    var result = sample
    result.deltaY = -sample.deltaY
    result.deltaX = -sample.deltaX
    return result
}
