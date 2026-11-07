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

/// The batteries to warn about now: at or below the threshold and not warned about yet.
/// A battery that is charged again (five points above the threshold) can warn once more.
public func lowBatteryAlerts(_ batteries: [AccessoryBattery], warned: Set<String>, threshold: Int = 20)
    -> (alerts: [AccessoryBattery], warned: Set<String>) {
    var still = warned
    var alerts: [AccessoryBattery] = []
    for battery in batteries {
        if battery.percent <= threshold {
            if still.insert(battery.name).inserted { alerts.append(battery) }
        } else if battery.percent > threshold + 5 {
            still.remove(battery.name)
        }
    }
    return (alerts, still)
}
