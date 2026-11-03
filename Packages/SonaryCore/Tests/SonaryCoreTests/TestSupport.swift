import SwiftUI
@testable import SonaryCore

struct Boom: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class FakeModule: SonaryModule {
    let id: String
    let title = LocalizedStringResource("Fake")
    let symbol = "star"
    var requiredPermissions: [SonaryPermission]
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(id: String, permissions: [SonaryPermission] = [], startError: (any Error)? = nil) {
        self.id = id
        self.requiredPermissions = permissions
        self.startError = startError
    }

    func start() async throws {
        startCount += 1
        if let startError { throw startError }
    }

    func stop() async { stopCount += 1 }
    func makeSettingsView() -> AnyView { AnyView(EmptyView()) }
}

struct FakeGate: PermissionGate {
    let result: Bool
    func ensure(_ permissions: [SonaryPermission]) async -> Bool { result }
}

final class FakeChecker: PermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [SonaryPermission: PermissionStatus]
    private let requestResult: PermissionStatus
    private var _statusCalls = 0
    private var _requested: [SonaryPermission] = []

    init(statuses: [SonaryPermission: PermissionStatus] = [:], requestResult: PermissionStatus = .granted) {
        self.statuses = statuses
        self.requestResult = requestResult
    }

    var statusCalls: Int { lock.withLock { _statusCalls } }
    var requested: [SonaryPermission] { lock.withLock { _requested } }

    func status(for permission: SonaryPermission) -> PermissionStatus {
        lock.withLock {
            _statusCalls += 1
            return statuses[permission] ?? .notDetermined
        }
    }

    func request(_ permission: SonaryPermission) async -> PermissionStatus {
        lock.withLock { _requested.append(permission) }
        return requestResult
    }
}

func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sonary.tests.\(UUID().uuidString)")!
}
