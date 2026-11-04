import Foundation

public enum MouseEventInput: Sendable {
    case scroll(ScrollSample)
    case buttonDown(button: Int, timestampNanoseconds: UInt64)
    /// The direction the mouse was pushed while the button was held, if far enough.
    case buttonUp(button: Int, direction: GestureDirection?)
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

    /// The gestures in force for this app, for the tap to know whether to watch a push.
    public func gestureMappings(for bundleID: String?) -> [GestureMapping] {
        effectiveSettings(settings, bundleID: bundleID).gestureMappings
    }

    public mutating func process(_ event: MouseEventInput, bundleID: String?) -> EventDecision {
        let effective = effectiveSettings(settings, bundleID: bundleID)
        switch event {
        case let .scroll(sample):
            guard isWheelEvent(sample) else { return .passThrough }
            // A sideways wheel is its own axis; when it has an action, it runs instead
            // of scrolling.
            if sample.deltaY == 0, let side = sideWheelDirection(deltaX: sample.deltaX) {
                let action = side == .left ? effective.sideWheelLeft : effective.sideWheelRight
                if action != ButtonAction.none { return .perform(action) }
            }
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
            // A button with gestures keeps its click until the button comes up, since
            // only then is it clear whether the mouse was pushed as well.
            if hasGestures(button: button, in: effective.gestureMappings) { return .swallow }
            if let mapped = action(forButton: button, in: effective.buttonMappings) {
                return mapped == .none ? .swallow : .perform(mapped)
            }
            return .passThrough
        case let .buttonUp(button, direction):
            if let direction,
               let gesture = action(forGesture: button, direction: direction, in: effective.gestureMappings) {
                return gesture == .none ? .swallow : .perform(gesture)
            }
            // No push, so the button's own action still applies.
            guard hasGestures(button: button, in: effective.gestureMappings) else { return .passThrough }
            if let mapped = action(forButton: button, in: effective.buttonMappings) {
                return mapped == .none ? .swallow : .perform(mapped)
            }
            return .swallow
        }
    }
}
