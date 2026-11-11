// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sonary contributors
//
// Not part of Vorssaint: Sonary's one door into this code. Sonary runs Vorssaint's features as
// they are, one group per Sonary module. A module that is on marks its group as installed and
// lets Vorssaint's own services start; a module that is off takes the group out again. Nothing
// of Vorssaint runs that no Sonary module asked for.

import AppKit
import Combine
import SwiftUI

public enum SonaryEngine {
    // MARK: - What belongs to which Sonary module

    /// Vorssaint's features by the Sonary module that switches them on. Notifications, online
    /// lyrics and the agent readouts of the island stay out: they read other apps or reach the
    /// network, which Sonary promises not to do unasked.
    private static let features: [String: [AppFeature]] = [
        "monitor": [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk,
                    .monitorPower, .connectedDevices, .fanControl],
        "mouse": [.scrollInverter, .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .smoothScroll,
                  .linearScroll, .scrollSpeed, .mouseAcceleration, .mouseNavigation,
                  .mouseButtonShortcuts, .middleClick, .mouseClickDebounce],
        "keyboard": [.superKey, .keyboardDebounce, .textSnippets, .quitWindowProtection],
        "notch": [.notch, .notchCalendar, .notchGestures, .notchTimer, .notchAccessories, .notchQueue,
                  .notchLiveEqualizer, .notchDownloads, .notchWatch, .notchMascot],
        "clipboard": [.clipboardHistory, .pastePlain, .finderCutPaste, .finderRename, .shelf,
                      .urlCleaner, .diskImageInstaller],
        "apps": [.cleaner, .uninstaller, .homebrew, .appUpdates, .autoQuit, .quitApps, .killProcess,
                 .portManager],
        "windows": [.windowLayout, .switcher, .dockPreview, .dockClick, .windowMaximizer, .spacesOrder],
        "display": [.brightness, .extraBrightness],
        "sound": [.mixer, .soundOutputSwitcher, .audioPriority, .micMute, .musicBlock],
        "awake": [.keepAwake, .bluetoothSleep],
        "tools": [.quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
                  .screenshot, .screenRecorder, .cameraPreview, .radialMenu, .scratchpad, .commandBar,
                  .wallpaper],
    ]

    /// The settings panes of a module, in the order Sonary lists them.
    public static func paneIDs(for area: String) -> [String] {
        SonaryPane.allCases.filter { $0.area == area }.map(\.rawValue)
    }

    // MARK: - Handlers Sonary sets

    private static var showPane: ((String, String) -> Void)?
    private static var openSettings: ((String?, String?) -> Void)?
    private static var closePanelHandler: (() -> Void)?
    private static var openPanelHandler: (() -> Void)?

    /// `showPane` selects a module's pane in Sonary's settings, `openSettings` also brings the
    /// settings window up, `openPanel` opens Sonary's menu panel (a click on a readout in the
    /// menu bar), `closePanel` closes it.
    public static func setHandlers(showPane: @escaping (String, String) -> Void,
                                   openSettings: @escaping (String?, String?) -> Void,
                                   openPanel: @escaping () -> Void,
                                   closePanel: @escaping () -> Void) {
        self.showPane = showPane
        self.openSettings = openSettings
        openPanelHandler = openPanel
        closePanelHandler = closePanel
    }

    // MARK: - Menu bar readouts

    /// Vorssaint's status item, kept for the monitor's readouts, the keep awake countdown and the
    /// clipboard preview. It shows no icon of its own (`SonaryHost.ownsMenuBarIcon`); a click on
    /// it opens Sonary's panel.
    private static var statusItems: StatusItemController?

    private static func installStatusItems() {
        guard statusItems == nil else { return }
        let controller = StatusItemController()
        controller.onLeftClick = { openPanelHandler?() }
        controller.onRightClick = { _ in openPanelHandler?() }
        controller.onMetricClick = { _, _ in openPanelHandler?() }
        controller.onClipboardPreviewClick = { ClipboardHistoryService.shared.toggleHistoryWindow() }
        statusItems = controller
    }

    private static func removeStatusItems() {
        statusItems?.sonaryRemoveMainItem()
        statusItems = nil
        SystemMonitor.shared.setMenuBarActive(false)
    }

    /// Whether a status bar window belongs to the readouts, not to Sonary's own menu bar icon.
    public static func ownsStatusWindow(_ window: NSWindow) -> Bool {
        statusItems?.sonaryOwns(window) ?? false
    }

    public static func setAccent(_ color: Color?) {
        SonaryIslandTint.accent = color
    }

    // MARK: - Helper runs

    /// Vorssaint starts its own executable again with an argument to put the mouse acceleration
    /// or the Super Key mapping back after the app is gone, and expects that run to do the
    /// clean-up and exit before any app is created (its `main.swift`, which Sonary does not
    /// use). Sonary calls this first thing at launch. Without it every such run came up as one
    /// more full copy of the app, which started helpers of its own.
    public static func runHelperIfRequestedAndExit() {
        let arguments = CommandLine.arguments
        guard arguments.contains(SuperKeyMappingGuard.cleanupArgument)
            || arguments.contains(MouseAccelerationGuard.cleanupArgument) else { return }
        Defaults.register()
        SuperKeyMappingGuard.runIfRequestedAndExit()
        MouseAccelerationGuard.runIfRequestedAndExit()
        // Asked for a clean-up this build does not know: never fall through into the app.
        exit(EXIT_FAILURE)
    }

    // MARK: - Starting and stopping

    private static var registered = false
    private static var runtimeReady = false
    private static var recoveredOnce = Set<String>()
    private static var cancellables = Set<AnyCancellable>()

    /// Registers Vorssaint's defaults once and starts with nothing installed: what counts as
    /// installed is decided by the Sonary modules that are on, on every launch.
    private static func register() {
        guard !registered else { return }
        registered = true
        Defaults.register()
        NotchControlItem.keyboardLightIsSupported = { false }
        let defaults = UserDefaults.standard
        for feature in AppFeature.allCases {
            defaults.set(false, forKey: feature.availabilityKey)
        }
        // The island's optional extensions are picked by Sonary, not by Vorssaint's first install.
        defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
    }

    /// What Vorssaint's app delegate sets up at launch, as far as the features need it.
    private static func prepareRuntime() {
        register()
        guard !runtimeReady else { return }
        runtimeReady = true
        GlobalShortcut.startObservingKeyboardLayout()
        HorizontalWheelScrolling.install()
        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        KeepAwakeManager.shared.onSessionEnded = { reason in
            let strings = L10n.shared.s
            switch reason {
            case .timer:
                Notifier.post(title: strings.notifySessionEndedTitle, body: strings.notifySessionEndedBody)
            case .battery:
                Notifier.post(title: strings.notifyBatteryTitle, body: strings.notifyBatteryBody)
            default:
                break
            }
        }
        Permissions.shared.refresh()
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.sync([
                    .scrollInverter, .scrollHorizontal, .scrollZoom, .scrollSpeed, .focusFollowsMouse,
                    .smoothScroll, .linearScroll, .mouseNavigation, .switcher, .dockPreview,
                    .finderCutPaste, .finderRename, .autoQuit, .dockClick, .middleClick,
                    .windowMaximizer, .keyboardDebounce, .windowLayout, .textSnippets, .brightness,
                    .radialMenu, .mouseButtonShortcuts, .mouseClickDebounce, .superKey,
                    .quitWindowProtection, .mixer, .musicBlock, .notch,
                ])
            }
            .store(in: &cancellables)
        Permissions.shared.$fullDiskAccess
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in FeatureRuntime.shared.sync([.uninstaller]) }
            .store(in: &cancellables)
        Permissions.shared.$screenRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in FeatureRuntime.shared.sync([.dockPreview, .screenRecorder]) }
            .store(in: &cancellables)
        // A link inside a pane ("open the shortcut settings") moves Vorssaint's router; Sonary
        // follows it to the module and pane that show the destination.
        SettingsRouter.shared.$page
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in followRouter() }
            .store(in: &cancellables)
    }

    private static func followRouter() {
        guard let pane = SonaryPane.showing(SettingsRouter.shared.destination) else { return }
        showPane?(pane.area, pane.rawValue)
    }

    /// Marks the module's features as installed and lets their services start.
    public static func start(_ area: String) {
        prepareRuntime()
        guard let group = features[area] else { return }
        let firstStart = recoveredOnce.insert(area).inserted
        if firstStart {
            switch area {
            case "mouse":
                // A change to the pointer acceleration left behind by a crash is put back.
                MouseAccelerationService.recoverPendingAtLaunch()
            case "windows":
                SystemShortcutTakeover.recoverIfNeeded(keeping: AppSwitcher.launchTakeoverIDs())
                SpacesOrderHold.recoverIfNeeded()
            case "display":
                BrightnessService.shared.restoreDisplaysLeftOff()
            default:
                break
            }
        }
        FeatureRuntime.shared.setAvailable(group, true)
        switch area {
        case "monitor":
            installStatusItems()
        case "notch":
            // The module's switch is the island's switch.
            UserDefaults.standard.set(true, forKey: DefaultsKey.notchEnabled)
            NotchService.shared.syncWithPreferences()
        case "awake" where firstStart:
            KeepAwakeManager.shared.recoverIfNeeded {
                KeepAwakeManager.shared.activateOnLaunchIfNeeded()
            }
        default:
            break
        }
    }

    /// Takes the module's features out again; their services stop.
    public static func stop(_ area: String) {
        guard runtimeReady, let group = features[area] else { return }
        if area == "notch" {
            UserDefaults.standard.set(false, forKey: DefaultsKey.notchEnabled)
        }
        if area == "monitor" { removeStatusItems() }
        FeatureRuntime.shared.setAvailable(group, false, enablingFirstInstalls: false)
    }

    /// Marks the module's features as installed without starting anything, so its panes can be
    /// drawn where the services must not run (Sonary's snapshot test).
    public static func installForPreview(_ area: String) {
        register()
        for feature in features[area] ?? [] {
            UserDefaults.standard.set(true, forKey: feature.availabilityKey)
        }
    }

    // MARK: - Views

    /// One of Vorssaint's settings panes, by the ID `paneIDs(for:)` lists. A pane scrolls on its
    /// own, so it wants the whole space below Sonary's page header.
    public static func settingsView(pane id: String) -> AnyView {
        register()
        guard let pane = SonaryPane(rawValue: id) else { return AnyView(EmptyView()) }
        return AnyView(pane.view.formStyle(.grouped).sonaryLook())
    }

    /// Every shortcut of the features that are installed.
    public static func shortcutsView() -> AnyView {
        register()
        return AnyView(ShortcutsSettings().formStyle(.grouped).sonaryLook())
    }

    /// The module's part of Vorssaint's menu panel, or nil when it has none.
    public static func panelView(for area: String) -> AnyView? {
        sections(for: area).map { AnyView($0.sonaryLook()) }
    }

    private static func sections(for area: String) -> AnyView? {
        switch area {
        case "monitor":
            return AnyView(SonaryMonitorPanel())
        case "sound":
            return AnyView(SonaryPanelStack {
                if AppFeature.mixer.isAvailable {
                    MixerSection(collapsible: false)
                } else {
                    AudioPrioritySection(collapsible: false)
                }
            })
        case "display":
            return AnyView(SonaryPanelStack { BrightnessSection(collapsible: false) })
        case "awake":
            return AnyView(SonaryPanelStack {
                KeepAwakeCard(collapsible: false)
                    .onAppear { KeepAwakeManager.shared.refreshPasswordlessStatus() }
            })
        case "tools":
            return AnyView(SonaryPanelStack {
                UtilitiesSection(collapsible: false, startCleaning: {
                    SonaryHost.closePanel()
                    CleaningModeManager.shared.activate()
                })
                QuickControlsSection(collapsible: false)
                QuickTogglesSection(collapsible: false)
            })
        default:
            return nil
        }
    }

    fileprivate static func requestSettings(_ pane: SonaryPane?) {
        openSettings?(pane?.area, pane?.rawValue)
    }

    fileprivate static func requestPanelClose() {
        closePanelHandler?()
    }
}

/// What Vorssaint's code asks of the app around it, now that the app is Sonary: its settings
/// window and its menu panel. Vorssaint's own app delegate is not running.
enum SonaryHost {
    /// The icon in the menu bar is Sonary's; Vorssaint's status item shows readouts only.
    static let ownsMenuBarIcon = true

    /// The title a pane carries above its cards. Sonary's page header already names the module,
    /// so the pane's own title is a sub-heading, not a second page title.
    static let paneTitleFont = Font.system(size: 15, weight: .semibold)

    /// Opens Sonary's settings on the pane Vorssaint's router points at.
    static func openSettingsWindow() {
        SonaryEngine.requestSettings(SonaryPane.showing(SettingsRouter.shared.destination))
    }

    static func closePanel() {
        SonaryEngine.requestPanelClose()
    }
}

/// The monitor's tab: Vorssaint's system, network, disk, power and fan sections, each folding on
/// its own. The monitor samples for them only while the tab is on screen.
private struct SonaryMonitorPanel: View {
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var showsDevices = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDevices {
                Button {
                    showsDevices = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                MetricDetailView(kind: .connectedDevices)
            } else {
                if features.isAvailable(.monitorCPU) || features.isAvailable(.monitorGPU)
                    || features.isAvailable(.monitorMemory) {
                    SystemSection(collapsible: true) { showsDevices = true }
                }
                if features.isAvailable(.monitorNetwork) { NetworkSection(collapsible: true) }
                if features.isAvailable(.monitorDisk) { DiskSection(collapsible: true) }
                if features.isAvailable(.monitorPower) { PowerSection(collapsible: true) }
                if features.isAvailable(.fanControl) { FanControlSection(collapsible: true) }
            }
        }
        .onAppear { sync(visible: true) }
        .onDisappear { sync(visible: false) }
        .onChange(of: showsDevices) { _ in sync(visible: true) }
    }

    private func sync(visible: Bool) {
        guard visible else {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
            return
        }
        SystemMonitor.shared.setMenuPanelNeeds(
            SystemMonitorPanelNeeds(system: true, network: true, disk: true, power: true, powerCard: true,
                                    connectedDevices: showsDevices))
    }
}

/// Sonary's accent for everything drawn from this module: controls follow the tint, and
/// `Color.accentColor`, which Vorssaint's views use throughout, follows the accent set here.
private extension View {
    func sonaryLook() -> some View {
        let accent = SonaryIslandTint.accent ?? Color.accentColor
        return tint(accent).accentColor(accent)
    }
}

/// The sections of one panel tab under each other, redrawn when a feature comes or goes.
private struct SonaryPanelStack<Content: View>: View {
    @ObservedObject private var features = FeatureRuntime.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .id(features.revision)
    }
}

/// Vorssaint's settings panes as Sonary lists them: each belongs to one Sonary module.
private enum SonaryPane: String, CaseIterable {
    case monitor
    case mouse
    case superKey, keyDebounce, textSnippets, quitProtection
    case notch, notchMascot
    case clipboard, cutPaste, shelf, urlCleaner
    case cleaner, uninstaller, homebrew, appUpdates, autoQuit, killProcess, portManager
    case windowLayout, switcher, dock
    case brightness, extraBrightness
    case mixer, soundOutput, audioPriority, musicBlocking
    case keepAwake, bluetoothSleep
    case quickTools, screenshot, commandBar, radialMenu, media, panelControls

    var area: String {
        switch self {
        case .monitor: return "monitor"
        case .mouse: return "mouse"
        case .superKey, .keyDebounce, .textSnippets, .quitProtection: return "keyboard"
        case .notch, .notchMascot: return "notch"
        case .clipboard, .cutPaste, .shelf, .urlCleaner: return "clipboard"
        case .cleaner, .uninstaller, .homebrew, .appUpdates, .autoQuit, .killProcess, .portManager:
            return "apps"
        case .windowLayout, .switcher, .dock: return "windows"
        case .brightness, .extraBrightness: return "display"
        case .mixer, .soundOutput, .audioPriority, .musicBlocking: return "sound"
        case .keepAwake, .bluetoothSleep: return "awake"
        case .quickTools, .screenshot, .commandBar, .radialMenu, .media, .panelControls: return "tools"
        }
    }

    /// Where the pane sits in Vorssaint's own settings window.
    var destination: FeatureSettingsDestination {
        switch self {
        case .monitor: return FeatureSettingsDestination(.monitor)
        case .panelControls: return FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration)
        case .mouse: return FeatureSettingsDestination(.mouse)
        case .superKey: return FeatureSettingsDestination(.superKey)
        case .keyDebounce: return FeatureSettingsDestination(.keyDebounce)
        case .textSnippets: return FeatureSettingsDestination(.textSnippets)
        case .quitProtection: return FeatureSettingsDestination(.quitProtection)
        case .notch: return FeatureSettingsDestination(.notch)
        case .notchMascot: return FeatureSettingsDestination(.notchMascot)
        case .clipboard: return FeatureSettingsDestination(.clipboard)
        case .cutPaste: return FeatureSettingsDestination(.cutPaste)
        case .shelf: return FeatureSettingsDestination(.shelf)
        case .urlCleaner: return FeatureSettingsDestination(.urlCleaner)
        case .cleaner: return FeatureSettingsDestination(.cleaner)
        case .uninstaller: return FeatureSettingsDestination(.uninstaller)
        case .homebrew: return FeatureSettingsDestination(.homebrew)
        case .appUpdates: return FeatureSettingsDestination(.appUpdates)
        case .autoQuit: return FeatureSettingsDestination(.autoQuit)
        case .killProcess: return FeatureSettingsDestination(.killProcess)
        case .portManager: return FeatureSettingsDestination(.portManager)
        case .windowLayout: return FeatureSettingsDestination(.windowLayout)
        case .switcher: return FeatureSettingsDestination(.switcher)
        case .dock: return FeatureSettingsDestination(.dock)
        case .brightness: return FeatureSettingsDestination(.energy, sectionAnchor: .brightness)
        case .extraBrightness: return FeatureSettingsDestination(.energy, sectionAnchor: .extraBrightness)
        case .mixer: return FeatureSettingsDestination(.general, sectionAnchor: .mixer)
        case .soundOutput: return FeatureSettingsDestination(.general, sectionAnchor: .soundOutputSwitcher)
        case .audioPriority: return FeatureSettingsDestination(.general, sectionAnchor: .audioPriority)
        case .musicBlocking: return FeatureSettingsDestination(.general, sectionAnchor: .musicBlocking)
        case .keepAwake: return FeatureSettingsDestination(.energy, sectionAnchor: .keepAwake)
        case .bluetoothSleep: return FeatureSettingsDestination(.energy, sectionAnchor: .bluetoothSleep)
        case .quickTools: return FeatureSettingsDestination(.quickTools)
        case .screenshot: return FeatureSettingsDestination(.screenshot)
        case .commandBar: return FeatureSettingsDestination(.commandBar)
        case .radialMenu: return FeatureSettingsDestination(.radialMenu)
        case .media: return FeatureSettingsDestination(.media)
        }
    }

    /// The pane that shows a destination of Vorssaint's router, if Sonary has one for it.
    static func showing(_ destination: FeatureSettingsDestination) -> SonaryPane? {
        if let anchor = destination.sectionAnchor,
           let exact = allCases.first(where: {
               $0.destination.page == destination.page && $0.destination.sectionAnchor == anchor
           }) {
            return exact
        }
        // Vorssaint's General page has no counterpart; Sonary has its own.
        if destination.page == .general { return nil }
        return allCases.first { $0.destination.page == destination.page }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .monitor: MonitorSettings()
        case .panelControls: GeneralToolSettings(anchor: .panelConfiguration)
        case .mouse: MouseSettings()
        case .superKey: SuperKeySettings()
        case .keyDebounce: KeyboardDebounceSettings()
        case .textSnippets: TextSnippetsSettings()
        case .quitProtection: QuitProtectionSettings()
        case .notch: NotchSettings()
        case .notchMascot: NotchMascotSettings()
        case .clipboard: ClipboardSettings()
        case .cutPaste: CutPasteSettings()
        case .shelf: ShelfSettings()
        case .urlCleaner: URLCleanerSettings()
        case .cleaner: CleanerSettings()
        case .uninstaller: UninstallerView()
        case .homebrew: HomebrewSettings()
        case .appUpdates: AppUpdatesSettings()
        case .autoQuit: AutoQuitSettings()
        case .killProcess: KillProcessView()
        case .portManager: PortManagerView()
        case .windowLayout: WindowLayoutSettings()
        case .switcher: SwitcherSettings()
        case .dock: DockSettings()
        case .brightness: EnergySettings(focus: .brightness)
        case .extraBrightness: EnergySettings(focus: .extraBrightness)
        case .mixer: GeneralToolSettings(anchor: .mixer)
        case .soundOutput: GeneralToolSettings(anchor: .soundOutputSwitcher)
        case .audioPriority: GeneralToolSettings(anchor: .audioPriority)
        case .musicBlocking: GeneralToolSettings(anchor: .musicBlocking)
        case .keepAwake: EnergySettings(focus: .keepAwake)
        case .bluetoothSleep: EnergySettings(focus: .bluetoothSleep)
        case .quickTools: QuickToolsSettings()
        case .screenshot: ScreenCaptureSettings()
        case .commandBar: CommandBarSettings()
        case .radialMenu: RadialMenuSettings()
        case .media: MediaSettings()
        }
    }
}

enum SonaryIslandTint {
    static var accent: Color?
}
