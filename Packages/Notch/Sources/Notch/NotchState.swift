import Foundation

public enum NotchPresentation: Equatable, Sendable {
    case collapsed
    case expanded
}

/// Hover opens the island and leaving closes it, unless a click pinned it open.
public struct NotchState: Equatable, Sendable {
    public private(set) var isHovering = false
    public private(set) var isPinned = false

    public init() {}

    public var presentation: NotchPresentation {
        (isHovering || isPinned) ? .expanded : .collapsed
    }

    public mutating func hoverChanged(_ inside: Bool) {
        isHovering = inside
    }

    public mutating func clicked() {
        isPinned.toggle()
    }

    /// A click outside the island releases the pin.
    public mutating func clickedOutside() {
        isPinned = false
    }
}
