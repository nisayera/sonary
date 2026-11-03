import CoreGraphics
import Foundation

/// macOS has no public API for display brightness. DisplayServices has one and every brightness
/// utility uses it, so it is looked up at runtime: if it ever goes away, Sonary falls back to
/// dimming with an overlay instead of failing to build or crashing.
enum DisplayServicesBridge {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static func brightness(of display: CGDirectDisplayID) -> Double? {
        guard let get = symbol("DisplayServicesGetBrightness", as: GetBrightness.self) else { return nil }
        var value: Float = 0
        guard get(display, &value) == 0, value.isFinite else { return nil }
        return clampedBrightness(Double(value))
    }

    @discardableResult
    static func setBrightness(_ value: Double, of display: CGDirectDisplayID) -> Bool {
        guard let set = symbol("DisplayServicesSetBrightness", as: SetBrightness.self) else { return false }
        return set(display, Float(clampedBrightness(value))) == 0
    }
}
