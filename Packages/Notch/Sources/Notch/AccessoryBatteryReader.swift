import Foundation
import IOKit

/// Battery levels of Bluetooth mice, keyboards, trackpads and headphones that report them to IOKit.
public enum AccessoryBatteryReader {
    public static func read() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                services.append(dictionary)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return parseAccessoryBatteries(services)
    }
}
