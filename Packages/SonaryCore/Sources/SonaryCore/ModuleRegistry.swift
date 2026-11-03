import Foundation
import Observation

@MainActor
@Observable
public final class ModuleRegistry {
    public let modules: [any SonaryModule]
    public private(set) var failures: [String: String] = [:]

    private var enabled: Set<String>
    private var running: Set<String> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let permissions: any PermissionGate

    public init(modules: [any SonaryModule], defaults: UserDefaults, permissions: any PermissionGate) {
        self.modules = modules
        self.defaults = defaults
        self.permissions = permissions
        self.enabled = Set(modules.map(\.id).filter { defaults.bool(forKey: Self.key($0)) })
    }

    public func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    public func setEnabled(_ id: String, _ on: Bool) async {
        guard let module = modules.first(where: { $0.id == id }) else { return }
        if on {
            await activate(module)
        } else {
            await deactivate(module)
        }
    }

    public func startEnabled() async {
        for module in modules where enabled.contains(module.id) && !running.contains(module.id) {
            await activate(module)
        }
    }

    // MARK: - Private

    private func activate(_ module: any SonaryModule) async {
        let id = module.id
        guard !running.contains(id) else { return }
        guard await permissions.ensure(module.requiredPermissions) else {
            fail(id, "Missing permission")
            return
        }
        do {
            try await module.start()
            running.insert(id)
            enabled.insert(id)
            failures[id] = nil
            defaults.set(true, forKey: Self.key(id))
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fail(id, text)
        }
    }

    private func deactivate(_ module: any SonaryModule) async {
        let id = module.id
        if running.contains(id) {
            await module.stop()
            running.remove(id)
        }
        enabled.remove(id)
        failures[id] = nil
        defaults.set(false, forKey: Self.key(id))
    }

    private func fail(_ id: String, _ message: String) {
        enabled.remove(id)
        failures[id] = message
        defaults.set(false, forKey: Self.key(id))
    }

    private static func key(_ id: String) -> String { "module.\(id).enabled" }
}
