import CoreGraphics

/// Which layout a window should take when it is dragged to an edge or a corner of the screen.
/// Corners win over edges, so the small corner areas are not swallowed by the long sides.
public func edgeLayout(for point: CGPoint, in visible: CGRect, threshold: CGFloat = 12) -> LayoutAction? {
    guard threshold > 0 else { return nil }
    let corner = max(threshold * 6, 80.0)
    let left = point.x - visible.minX <= threshold
    let right = visible.maxX - point.x <= threshold
    let top = visible.maxY - point.y <= threshold
    let bottom = point.y - visible.minY <= threshold
    guard left || right || top || bottom else { return nil }
    // A drag may slip a little past the edge, but a pointer far outside this screen
    // belongs to another one and must not snap here.
    guard visible.insetBy(dx: -threshold, dy: -threshold).contains(point) else { return nil }

    let nearLeft = point.x - visible.minX <= corner
    let nearRight = visible.maxX - point.x <= corner
    let nearTop = visible.maxY - point.y <= corner
    let nearBottom = point.y - visible.minY <= corner

    if top, nearLeft { return .topLeft }
    if top, nearRight { return .topRight }
    if bottom, nearLeft { return .bottomLeft }
    if bottom, nearRight { return .bottomRight }
    if left, nearTop { return .topLeft }
    if left, nearBottom { return .bottomLeft }
    if right, nearTop { return .topRight }
    if right, nearBottom { return .bottomRight }
    if top { return .maximize }
    if left { return .leftHalf }
    if right { return .rightHalf }
    return .bottomHalf
}

/// The window the pointer is over, for focus-follows-mouse. Windows are listed front to back,
/// so the first match is the one actually under the pointer.
public func windowUnder(_ point: CGPoint, in windows: [(pid: Int32, frame: CGRect)]) -> Int32? {
    windows.first { $0.frame.contains(point) }?.pid
}

/// Whether the pointer has rested long enough on a new app to hand it the focus.
public struct FocusFollowState: Sendable {
    public var delay: Double
    private var candidate: Int32?
    private var since: Double?

    public init(delay: Double = 0.35) {
        self.delay = delay
    }

    /// Returns the app to focus once the pointer has stayed over it for the delay, and only once.
    public mutating func pointer(over pid: Int32?, at time: Double, focused: Int32?) -> Int32? {
        guard let pid, pid != focused else {
            candidate = nil
            since = nil
            return nil
        }
        if candidate != pid {
            candidate = pid
            since = time
            return nil
        }
        guard let since, time - since >= delay else { return nil }
        candidate = nil
        self.since = nil
        return pid
    }
}
