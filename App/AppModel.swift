import Foundation
import Observation
import Monitor
import Mouse
import Notch
import SonaryCore

@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let broker: PermissionBroker
    let launchAtLogin = LaunchAtLoginModel()
    let monitor: MonitorModule
    let mouse: MouseModule
    let notch: NotchModule
    let updates: UpdateModel
    private(set) var onboardingCompleted: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, startUpdater: Bool = true) {
        let broker = PermissionBroker()
        self.broker = broker
        self.defaults = defaults
        self.updates = UpdateModel(startUpdater: startUpdater)
        let monitor = MonitorModule(defaults: defaults)
        self.monitor = monitor
        let mouse = MouseModule(defaults: defaults)
        self.mouse = mouse
        let notch = NotchModule(defaults: defaults)
        self.notch = notch
        self.registry = ModuleRegistry(modules: [monitor, mouse, notch], defaults: defaults, permissions: broker)
        self.onboardingCompleted = defaults.bool(forKey: "onboarding.completed")
    }

    /// True while the app is the host of the unit-test bundle (Sparkle must not start then).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
