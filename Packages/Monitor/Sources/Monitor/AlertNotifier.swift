import Foundation
import UserNotifications

public struct AlertNotifier: Sendable {
    public init() {}

    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func send(_ kind: AlertKind) async {
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: kind)
        content.body = Self.body(for: kind)
        let request = UNNotificationRequest(identifier: "sonary.alert.\(kind)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func title(for kind: AlertKind) -> String {
        switch kind {
        case .sustainedCPU: String(localized: "High CPU load", bundle: .module)
        case .highTemperature: String(localized: "High temperature", bundle: .module)
        case .memoryPressure: String(localized: "Memory pressure", bundle: .module)
        case .lowDisk: String(localized: "Low disk space", bundle: .module)
        case .lowBattery: String(localized: "Low battery", bundle: .module)
        }
    }

    static func body(for kind: AlertKind) -> String {
        switch kind {
        case .sustainedCPU: String(localized: "The CPU has been under heavy load for a while.", bundle: .module)
        case .highTemperature: String(localized: "A chip temperature is unusually high.", bundle: .module)
        case .memoryPressure: String(localized: "The system is running low on memory.", bundle: .module)
        case .lowDisk: String(localized: "Free disk space is almost used up.", bundle: .module)
        case .lowBattery: String(localized: "Plug in your Mac soon.", bundle: .module)
        }
    }
}
