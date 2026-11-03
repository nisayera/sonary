import ApplicationServices
import UserNotifications

public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

public protocol PermissionChecking: Sendable {
    func status(for permission: SonaryPermission) -> PermissionStatus
    func request(_ permission: SonaryPermission) async -> PermissionStatus
}

public actor PermissionBroker: PermissionGate {
    private let checker: any PermissionChecking

    public init(checker: any PermissionChecking = SystemPermissionChecker()) {
        self.checker = checker
    }

    public func ensure(_ permissions: [SonaryPermission]) async -> Bool {
        var allGranted = true
        for permission in permissions {
            var current = checker.status(for: permission)
            if current != .granted {
                current = await checker.request(permission)
            }
            if current != .granted { allGranted = false }
        }
        return allGranted
    }
}

public struct SystemPermissionChecker: PermissionChecking {
    public init() {}

    public func status(for permission: SonaryPermission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        default:
            return .notDetermined
        }
    }

    public func request(_ permission: SonaryPermission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .granted : .denied
        default:
            return .notDetermined
        }
    }
}
