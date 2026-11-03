import Foundation

public enum NotchGestureAction: Equatable, Sendable {
    case open
    case close
    case nextWidget
    case previousWidget
}

/// Turns scrolling on the island into actions. Deltas follow AppKit: scrolling down is negative,
/// scrolling right is negative. Small movements are collected until they add up to a real gesture.
public struct NotchGestureState: Sendable {
    public var threshold: Double
    private var accumulatedY = 0.0
    private var accumulatedX = 0.0

    public init(threshold: Double = 12) {
        self.threshold = threshold
    }

    public mutating func reset() {
        accumulatedY = 0
        accumulatedX = 0
    }

    public mutating func scrolled(deltaX: Double, deltaY: Double, presentation: NotchPresentation) -> NotchGestureAction? {
        accumulatedY += deltaY
        accumulatedX += deltaX
        // The bigger movement decides, so a diagonal swipe does not do two things at once.
        if abs(accumulatedX) > abs(accumulatedY) {
            guard presentation == .expanded, abs(accumulatedX) >= threshold else { return nil }
            let action: NotchGestureAction = accumulatedX < 0 ? .nextWidget : .previousWidget
            reset()
            return action
        }
        guard abs(accumulatedY) >= threshold else { return nil }
        let action: NotchGestureAction? = switch presentation {
        case .collapsed: accumulatedY < 0 ? .open : nil
        case .expanded: accumulatedY > 0 ? .close : nil
        }
        if action != nil { reset() }
        return action
    }
}

/// The widget after (or before) the current one, wrapping around. Nil when there is nothing to switch to.
public func neighbourWidget(_ current: NotchWidget, in widgets: [NotchWidget], forward: Bool) -> NotchWidget? {
    guard widgets.count > 1, let index = widgets.firstIndex(of: current) else { return widgets.first }
    let next = forward ? (index + 1) % widgets.count : (index - 1 + widgets.count) % widgets.count
    return widgets[next]
}
