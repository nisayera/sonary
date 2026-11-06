import CoreGraphics
import Foundation

public struct ScrollModifierSet: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = ScrollModifierSet(rawValue: 1 << 0)
    public static let control = ScrollModifierSet(rawValue: 1 << 1)
    public static let option = ScrollModifierSet(rawValue: 1 << 2)
    public static let command = ScrollModifierSet(rawValue: 1 << 3)
}

public enum ScrollModifier: String, CaseIterable, Codable, Sendable {
    case none, shift, control, option, command

    var set: ScrollModifierSet? {
        switch self {
        case .none: nil
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }
}

/// The parts of a scroll event the mouse module cares about.
public struct ScrollSample: Equatable, Sendable {
    public var deltaY: Double
    public var deltaX: Double
    public var isContinuous: Bool
    public var scrollPhase: Int
    public var momentumPhase: Int
    public var modifiers: ScrollModifierSet

    public init(deltaY: Double, deltaX: Double = 0, isContinuous: Bool = false, scrollPhase: Int = 0,
                momentumPhase: Int = 0, modifiers: ScrollModifierSet = []) {
        self.deltaY = deltaY
        self.deltaX = deltaX
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.modifiers = modifiers
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

/// Reverses the scroll direction of wheel events only, both axes.
public func reversed(_ sample: ScrollSample) -> ScrollSample {
    reversed(sample, vertical: true, horizontal: true)
}

/// Reverses a wheel's vertical and sideways scrolling, each on its own.
public func reversed(_ sample: ScrollSample, vertical: Bool, horizontal: Bool) -> ScrollSample {
    guard isWheelEvent(sample), vertical || horizontal else { return sample }
    var result = sample
    if vertical { result.deltaY = -sample.deltaY }
    if horizontal { result.deltaX = -sample.deltaX }
    return result
}

/// While the chosen key is held, a wheel notch zooms instead of scrolling: ⌘= up, ⌘- down,
/// the zoom shortcut nearly every app understands. Nil when the wheel should just scroll.
public func zoomAction(for sample: ScrollSample, whileHolding modifier: ScrollModifier) -> ButtonAction? {
    guard isWheelEvent(sample), let wanted = modifier.set, sample.modifiers.contains(wanted),
          sample.deltaY != 0 else { return nil }
    let command = UInt64(CGEventFlags.maskCommand.rawValue)
    return .keyboardShortcut(keyCode: sample.deltaY > 0 ? 24 : 27, modifiers: command)
}

/// Turns a wheel's vertical scrolling into horizontal scrolling while the chosen key is held.
public func horizontalized(_ sample: ScrollSample, whileHolding modifier: ScrollModifier) -> ScrollSample {
    guard isWheelEvent(sample), let wanted = modifier.set, sample.modifiers.contains(wanted),
          sample.deltaY != 0 else { return sample }
    var result = sample
    result.deltaX = sample.deltaY
    result.deltaY = 0
    return result
}
