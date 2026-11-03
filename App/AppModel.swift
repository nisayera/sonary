import Foundation
import Observation
import Monitor
import SonaryCore

@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let broker: PermissionBroker
    let launchAtLogin = LaunchAtLoginModel()
    let monitor: MonitorModule
    private(set) var onboardingCompleted: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        let broker = PermissionBroker()
        self.broker = broker
        self.defaults = defaults
        let monitor = MonitorModule(defaults: defaults)
        self.monitor = monitor
        self.registry = ModuleRegistry(modules: [monitor], defaults: defaults, permissions: broker)
        self.onboardingCompleted = defaults.bool(forKey: "onboarding.completed")
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: "onboarding.completed")
    }

    func resetOnboarding() {
        onboardingCompleted = false
        defaults.set(false, forKey: "onboarding.completed")
    }
}
