import Foundation

/// Turns the Bluetooth controller off and on again. IOBluetooth has no public API for
/// this, so the two symbols are looked up at runtime: when they are missing, Sonary
/// leaves Bluetooth alone instead of guessing.
enum BluetoothPower {
    private typealias SetPower = @convention(c) (Int32) -> Int32
    private typealias GetPower = @convention(c) (UnsafeMutablePointer<Int32>) -> Int32

    private nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// True when Sonary can actually switch Bluetooth, so the setting can say so.
    static var isAvailable: Bool {
        symbol("IOBluetoothPreferenceSetControllerPowerState", as: SetPower.self) != nil
    }

    static var isOn: Bool? {
        guard let get = symbol("IOBluetoothPreferenceGetControllerPowerState", as: GetPower.self) else { return nil }
        var state: Int32 = 0
        guard get(&state) == 0 else { return nil }
        return state != 0
    }

    @discardableResult
    static func set(on: Bool) -> Bool {
        guard let set = symbol("IOBluetoothPreferenceSetControllerPowerState", as: SetPower.self) else { return false }
        return set(on ? 1 : 0) == 0
    }
}

/// Whether Bluetooth should be switched back on when the Mac wakes: only when Sonary
/// is the one that turned it off, so a user who switched it off stays switched off.
public func shouldRestoreBluetooth(turnedOffBySonary: Bool, settingEnabled: Bool) -> Bool {
    turnedOffBySonary && settingEnabled
}
