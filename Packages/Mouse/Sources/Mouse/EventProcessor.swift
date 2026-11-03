import Foundation

public enum MouseEventInput: Sendable {
    case scroll(ScrollSample)
    case buttonDown(button: Int, timestampNanoseconds: UInt64)
}

public enum EventDecision: Equatable, Sendable {
    case passThrough
    case replaceScroll(ScrollSample)
    case swallow
    case perform(ButtonAction)
    case injectSmooth(ScrollSample)
}

/// Decides what to do with each mouse event. Pure logic, no system calls.
public struct EventProcessor: Sendable {
    private var settings: MouseSettings
    private var clickFilter: ClickFilter

    public init(settings: MouseSettings) {
        self.settings = settings
        self.clickFilter = ClickFilter(milliseconds: settings.clickFilterMilliseconds)
    }

    public mutating func update(settings: MouseSettings) {
        if settings.clickFilterMilliseconds != self.settings.clickFilterMilliseconds {
            clickFilter = ClickFilter(milliseconds: settings.clickFilterMilliseconds)
        }
        self.settings = settings
    }

    public mutating func process(_ event: MouseEventInput, bundleID: String?) -> EventDecision {
        let effective = effectiveSettings(settings, bundleID: bundleID)
        switch event {
        case let .scroll(sample):
            guard isWheelEvent(sample) else { return .passThrough }
            var result = sample
            if effective.linearScroll { result = linearized(result, linesPerStep: effective.scrollLinesPerStep) }
            if effective.reverseScroll { result = reversed(result) }
            result = horizontalized(result, whileHolding: effective.horizontalScrollModifier)
            if effective.smoothScroll { return .injectSmooth(result) }
            return result == sample ? .passThrough : .replaceScroll(result)
        case let .buttonDown(button, timestamp):
            if effective.clickFilterMilliseconds > 0,
               clickFilter.shouldDrop(button: button, timestampNanoseconds: timestamp) {
                return .swallow
            }
            if let mapped = action(forButton: button, in: effective.buttonMappings) {
                return mapped == .none ? .swallow : .perform(mapped)
            }
            return .passThrough
        }
    }
}
