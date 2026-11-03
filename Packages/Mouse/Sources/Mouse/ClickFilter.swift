import Foundation

/// Drops accidental repeat clicks (worn switches, double-click glitches).
public struct ClickFilter: Sendable {
    private let windowNanoseconds: UInt64
    private var lastDown: [Int: UInt64] = [:]

    public init(milliseconds: Int) {
        windowNanoseconds = UInt64(max(milliseconds, 0)) * 1_000_000
    }

    /// Returns true when this mouse-down comes too soon after the previous one of the same button.
    public mutating func shouldDrop(button: Int, timestampNanoseconds: UInt64) -> Bool {
        guard windowNanoseconds > 0 else { return false }
        if let last = lastDown[button], timestampNanoseconds >= last,
           timestampNanoseconds - last < windowNanoseconds {
            return true
        }
        // First click, outside the window, or the clock went backwards: accept and remember.
        lastDown[button] = timestampNanoseconds
        return false
    }
}
