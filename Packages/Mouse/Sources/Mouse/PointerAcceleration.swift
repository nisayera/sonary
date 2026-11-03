import Foundation
import IOKit
import IOKit.hidsystem

public protocol AccelerationControlling: Sendable {
    func read() -> Double?
    func write(_ value: Double) -> Bool
}

/// Reads and writes the system mouse acceleration through IOHID. A value of -1 turns acceleration off.
public struct IOHIDAccelerationControl: AccelerationControlling {
    public init() {}

    public func read() -> Double? {
        let handle = NXOpenEventStatus()
        guard handle != 0 else { return nil }
        defer { NXCloseEventStatus(handle) }
        var value = 0.0
        let result = IOHIDGetAccelerationWithKey(handle, kIOHIDMouseAccelerationType as CFString, &value)
        return result == KERN_SUCCESS ? value : nil
    }

    public func write(_ value: Double) -> Bool {
        let handle = NXOpenEventStatus()
        guard handle != 0 else { return false }
        defer { NXCloseEventStatus(handle) }
        return IOHIDSetAccelerationWithKey(handle, kIOHIDMouseAccelerationType as CFString, value) == KERN_SUCCESS
    }
}

/// Turns acceleration off and always puts the original value back (also after a crash).
public final class AccelerationGuard: @unchecked Sendable {
    private let control: any AccelerationControlling
    private let defaults: UserDefaults
    private let key = "mouse.accel.original"
    private let lock = NSLock()

    public init(control: any AccelerationControlling, defaults: UserDefaults) {
        self.control = control
        self.defaults = defaults
    }

    @discardableResult
    public func disable() -> Bool {
        lock.withLock {
            if defaults.object(forKey: key) == nil {
                guard let original = control.read() else { return false }
                defaults.set(original, forKey: key)
            }
            return control.write(-1)
        }
    }

    public func restore() {
        lock.withLock {
            guard let original = defaults.object(forKey: key) as? Double else { return }
            if control.write(original) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Call on start: if a previous run left acceleration off, restore it first.
    public func recoverIfNeeded() { restore() }
}
