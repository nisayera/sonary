import Foundation
import Observation
import Monitor
import Apps
import Clipboard
import Mouse
import Notch
import SonaryCore
import Sound
import Tools
import Windows

@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let broker: PermissionBroker
    let launchAtLogin = LaunchAtLoginModel()
    let monitor: MonitorModule
    let mouse: MouseModule
    let notch: NotchModule
    let clipboard: ClipboardModule
    let apps: AppsModule
    let windows: WindowsModule
    let sound: SoundModule
    let tools: ToolsModule
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
        let clipboard = ClipboardModule(defaults: defaults)
        self.clipboard = clipboard
        let apps = AppsModule()
        self.apps = apps
        let windows = WindowsModule(defaults: defaults)
        self.windows = windows
        let sound = SoundModule(defaults: defaults)
        self.sound = sound
        let tools = ToolsModule(defaults: defaults)
        self.tools = tools
        self.registry = ModuleRegistry(modules: [monitor, mouse, notch, clipboard, apps, windows, sound, tools], defaults: defaults, permissions: broker)
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
