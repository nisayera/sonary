public enum SonaryPermission: String, Sendable, CaseIterable, Codable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case fullDiskAccess
    case notifications
    case calendars
}

public protocol PermissionGate: Sendable {
    /// Returns true when every listed permission is granted (requesting missing ones).
    func ensure(_ permissions: [SonaryPermission]) async -> Bool
}
