import Foundation

public struct AccessoryBattery: Equatable, Sendable, Identifiable {
    public var name: String
    public var percent: Int
    public var id: String { name }

    public init(name: String, percent: Int) {
        self.name = name
        self.percent = percent
    }
}

/// Turns IOKit HID service properties into a sorted list of named batteries.
public func parseAccessoryBatteries(_ services: [[String: Any]]) -> [AccessoryBattery] {
    var byName: [String: AccessoryBattery] = [:]
    for service in services {
        guard let name = service["Product"] as? String, !name.isEmpty,
              let raw = (service["BatteryPercent"] as? NSNumber)?.intValue else { continue }
        byName[name] = AccessoryBattery(name: name, percent: min(max(raw, 0), 100))
    }
    return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
