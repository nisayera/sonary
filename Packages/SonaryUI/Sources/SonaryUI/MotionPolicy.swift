import SwiftUI

public enum SonaryMotion {
    /// Spring duration in seconds. Must stay below 0.5 s.
    public static let springDuration: Double = 0.4
    public static let fadeDuration: Double = 0.15
}

public extension Animation {
    static var sonarySpring: Animation { .spring(duration: SonaryMotion.springDuration, bounce: 0.15) }
}

/// Returns the spring, or a short opacity fade when Reduce Motion is enabled.
public func sonaryAnimation(_ reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: SonaryMotion.fadeDuration) : .sonarySpring
}
