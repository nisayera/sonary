import Foundation

/// Spreads scroll impulses over time (exponential easing) so wheel scrolling looks smooth.
/// The sum of everything returned by `step` converges to the sum of all added impulses.
public struct SmoothScroller: Sendable {
    private let tau: Double
    private var remainingY = 0.0
    private var remainingX = 0.0

    /// `smoothness` is 0...1; 0 releases every impulse immediately.
    public init(smoothness: Double) {
        let clamped = min(max(smoothness, 0), 1)
        tau = clamped * 0.25
    }

    public var isIdle: Bool { remainingY == 0 && remainingX == 0 }

    public mutating func add(deltaY: Double, deltaX: Double) {
        remainingY += deltaY
        remainingX += deltaX
    }

    public mutating func step(dt: Double) -> (dy: Double, dx: Double) {
        guard dt > 0 else { return (0, 0) }
        let fraction = tau == 0 ? 1.0 : 1 - exp(-dt / tau)
        let dy = release(&remainingY, fraction: fraction)
        let dx = release(&remainingX, fraction: fraction)
        return (dy, dx)
    }

    private func release(_ remaining: inout Double, fraction: Double) -> Double {
        let part = remaining * fraction
        if abs(remaining - part) < 0.01 {
            let all = remaining
            remaining = 0
            return all
        }
        remaining -= part
        return part
    }
}
