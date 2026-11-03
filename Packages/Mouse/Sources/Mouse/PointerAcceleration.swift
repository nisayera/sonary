import Foundation
import IOKit
import IOKit.hidsystem

public protocol AccelerationControlling: Sendable {
    func read() -> Double?
    func write(_ value: Double) -> Bool
}

/// Reads and writes the system mouse acceleration through the IOHIDSystem service.
/// The system stores it as a 16.16 fixed-point number; -1 turns acceleration off.
public struct IOHIDAccelerationControl: AccelerationControlling {
    private static let key = "HIDMouseAcceleration" as CFString

    public init() {}

    private func withConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, task_self_trap(), UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(connect) }
        return body(connect)
    }

    public func read() -> Double? {
        withConnection { connect in
            var raw: Int32 = 0
            var size: IOByteCount = 0
            let result = withUnsafeMutablePointer(to: &raw) { pointer in
                IOHIDGetParameter(connect, Self.key, IOByteCount(MemoryLayout<Int32>.size), pointer, &size)
            }
            return result == KERN_SUCCESS ? Double(raw) / 65536.0 : nil
        }
    }

    public func write(_ value: Double) -> Bool {
        withConnection { connect in
            var raw = Int32((value * 65536.0).rounded())
            let result = withUnsafeMutablePointer(to: &raw) { pointer in
                IOHIDSetParameter(connect, Self.key, pointer, IOByteCount(MemoryLayout<Int32>.size))
            }
            return result == KERN_SUCCESS
        } ?? false
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
