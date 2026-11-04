import Foundation
import Observation
import Keyboard
import Monitor
import Apps
import Clipboard
import Display
import Mouse
import Notch
import SonaryCore
import SonaryUI
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
    let keyboard: KeyboardModule
    let display: DisplayModule
    let updates: UpdateModel
    private(set) var onboardingCompleted: Bool
    /// How see-through Sonary's floating surfaces are.
    private(set) var appearance: SonaryAppearance

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
        let apps = AppsModule(defaults: defaults)
        self.apps = apps
        let windows = WindowsModule(defaults: defaults)
        self.windows = windows
        let sound = SoundModule(defaults: defaults)
        self.sound = sound
        let tools = ToolsModule(defaults: defaults)
        self.tools = tools
        let keyboard = KeyboardModule(defaults: defaults)
        self.keyboard = keyboard
        // The Super Key's tap action can open the command bar, which the tools module owns.
        keyboard.model.commandBarAction = { [weak tools] in tools?.model.showCommandBar() }
        // The command bar can also paste from the clipboard history.
        tools.model.externalCommands = { [weak clipboard] in
            guard let clipboard else { return [] }
            return clipboard.model.history.entries.prefix(20).compactMap { entry in
                guard let text = entry.text, !text.isEmpty else { return nil }
                return ExternalCommand(id: entry.id.uuidString, title: text, symbol: "doc.on.clipboard") {
                    clipboard.model.copy(entry)
                }
            }
        }
        let display = DisplayModule(defaults: defaults)
        self.display = display
        self.registry = ModuleRegistry(modules: [monitor, mouse, keyboard, notch, clipboard, apps, windows, display, sound, tools], defaults: defaults, permissions: broker)
        self.onboardingCompleted = defaults.bool(forKey: "onboarding.completed")
        self.appearance = SonaryAppearance.stored(in: defaults)
    }

    /// True while the app is the host of the unit-test bundle (Sparkle must not start then).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func setAppearance(_ value: SonaryAppearance) {
        appearance = value
        value.store(in: defaults)
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
