import Foundation
import Observation
import SonaryCore

@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let broker: PermissionBroker
    let launchAtLogin = LaunchAtLoginModel()
    private(set) var onboardingCompleted: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        let broker = PermissionBroker()
        self.broker = broker
        self.defaults = defaults
        self.registry = ModuleRegistry(modules: [], defaults: defaults, permissions: broker)
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
