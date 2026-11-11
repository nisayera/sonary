import AppKit
import Foundation
import Observation
import Monitor
import SonaryCore
import SonaryUI
import Vorssaint

@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let broker: PermissionBroker
    let launchAtLogin = LaunchAtLoginModel()
    let monitor: MonitorModule
    let updates: UpdateModel
    private(set) var onboardingCompleted: Bool
    /// How see-through Sonary's floating surfaces are.
    private(set) var appearance: SonaryAppearance
    /// The page the settings window shows; the panel sets it before opening the window.
    var settingsPage: SettingsDestination = .general
    /// The module tabs of the menu panel the user placed first, by module ID.
    private(set) var panelTabOrder: [String]
    /// Module tabs the user keeps out of the menu panel.
    private(set) var hiddenPanelTabs: Set<String>
    /// Set after an update until the user has looked at what changed or dismissed it.
    private(set) var updatedToVersion: String?
    /// What the panel's header and overview show.
    private(set) var panelOptions: PanelOptions
    /// The pane each engine module's settings page shows, by module ID.
    var enginePanes: [String: String] = [:]
    /// Opens the settings window; set by a view, which is where SwiftUI hands the action out.
    @ObservationIgnored var openSettingsWindow: (() -> Void)?

    @ObservationIgnored let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, startUpdater: Bool = true) {
        let broker = PermissionBroker()
        self.broker = broker
        self.defaults = defaults
        self.updates = UpdateModel(startUpdater: startUpdater)
        let monitor = MonitorModule(defaults: defaults)
        self.monitor = monitor
        ShortcutStore.shared.configure(defaults: defaults)
        // Everything but the system monitor is Vorssaint's work for now, one engine module per
        // group of its features. The module IDs are the ones Sonary's own modules had, so what
        // was on stays on.
        let engines: [any SonaryModule] = [
            EngineModule(id: "mouse", title: "Mouse", symbol: "computermouse"),
            EngineModule(id: "keyboard", title: "Keyboard", symbol: "keyboard"),
            EngineModule(id: "notch", title: "Notch", symbol: "capsule.portrait.tophalf.filled"),
            EngineModule(id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard"),
            EngineModule(id: "apps", title: "Apps", symbol: "square.stack.3d.up"),
            EngineModule(id: "windows", title: "Windows", symbol: "macwindow.on.rectangle"),
            EngineModule(id: "display", title: "Display", symbol: "sun.max"),
            EngineModule(id: "sound", title: "Sound", symbol: "speaker.wave.2"),
            EngineModule(id: "awake", title: "Keep awake", symbol: "cup.and.saucer"),
            EngineModule(id: "tools", title: "Tools", symbol: "wrench.and.screwdriver"),
        ]
        // Keep awake used to be part of sound; whoever had sound on keeps keep awake on.
        if defaults.object(forKey: "module.awake.enabled") == nil, defaults.bool(forKey: "module.sound.enabled") {
            defaults.set(true, forKey: "module.awake.enabled")
        }
        self.registry = ModuleRegistry(modules: [monitor as any SonaryModule] + engines,
                                       defaults: defaults, permissions: broker,
                                       missingPermissionText: { missingPermissionText($0) })
        self.onboardingCompleted = defaults.bool(forKey: "onboarding.completed")
        self.appearance = SonaryAppearance.stored(in: defaults)
        self.panelTabOrder = defaults.stringArray(forKey: "panel.tabs.order") ?? []
        self.hiddenPanelTabs = Set(defaults.stringArray(forKey: "panel.tabs.hidden") ?? [])
        self.panelOptions = StoredSettings.load(PanelOptions.self, key: "panel.options", from: defaults,
                                                fallback: PanelOptions())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let seen = defaults.string(forKey: "app.lastVersion")
        // A first launch has nothing new to tell; only a change of version does.
        self.updatedToVersion = seen != nil && seen != version && !version.isEmpty ? version : nil
        defaults.set(version, forKey: "app.lastVersion")
        // Vorssaint's code asks for the settings window and the menu panel; they are Sonary's.
        SonaryEngine.setHandlers(
            showPane: { [weak self] area, pane in self?.showEnginePane(area, pane) },
            openSettings: { [weak self] area, pane in
                if let area, let pane { self?.showEnginePane(area, pane) }
                NSApp.activate()
                self?.openSettingsWindow?()
            },
            closePanel: { [weak self] in self?.closePanelIfOpen() })
    }

    /// Selects a module's page in the settings, and the pane on it.
    func showEnginePane(_ area: String, _ pane: String) {
        enginePanes[area] = pane
        settingsPage = .module(area)
    }

    func setPanelTabOrder(_ order: [String]) {
        panelTabOrder = order
        defaults.set(order, forKey: "panel.tabs.order")
    }

    func setPanelTab(_ id: String, hidden: Bool) {
        if hidden { hiddenPanelTabs.insert(id) } else { hiddenPanelTabs.remove(id) }
        defaults.set(Array(hiddenPanelTabs).sorted(), forKey: "panel.tabs.hidden")
    }

    func updatePanelOptions(_ change: (inout PanelOptions) -> Void) {
        change(&panelOptions)
        if let data = try? JSONEncoder().encode(panelOptions) { defaults.set(data, forKey: "panel.options") }
    }

    func dismissWhatsNew() {
        updatedToVersion = nil
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
