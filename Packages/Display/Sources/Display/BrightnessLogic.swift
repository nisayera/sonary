import CoreGraphics
import Foundation

public struct DisplayInfo: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var isBuiltIn: Bool
    /// False when only the software overlay can dim this display.
    public var hasHardwareControl: Bool
    public var brightness: Double

    public init(id: UInt32, name: String, isBuiltIn: Bool, hasHardwareControl: Bool, brightness: Double) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.hasHardwareControl = hasHardwareControl
        self.brightness = brightness
    }
}

public func clampedBrightness(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

/// One keyboard step up or down, like the brightness keys.
public func steppedBrightness(_ current: Double, up: Bool, steps: Int = 16) -> Double {
    let step = 1.0 / Double(max(steps, 1))
    return clampedBrightness((current + (up ? step : -step) * 1.0001).rounded(toStep: step))
}

private extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}

/// How dark the overlay has to be for a display without hardware control.
/// Never fully black, so the screen cannot be dimmed into uselessness.
public func overlayAlpha(for brightness: Double, maximumDim: Double = 0.75) -> Double {
    (1 - clampedBrightness(brightness)) * min(max(maximumDim, 0), 0.95)
}
