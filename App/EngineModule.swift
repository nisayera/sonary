import Foundation
import Observation
import SonaryCore
import SonaryUI
import SwiftUI
import Vorssaint

/// A module whose work is done by Vorssaint's code, taken over as it is (see `Vendor/Vorssaint`
/// and NOTICE). Sonary switches the module's features on and off, hands them the accent colour,
/// and shows Vorssaint's settings panes and panel sections for them. Each one is meant to give
/// way to a module of Sonary's own later, one at a time.
@MainActor
@Observable
final class EngineModule: SonaryModule {
    let id: String
    let title: LocalizedStringResource
    let symbol: String
    /// True while the module's features are installed, so their panes have something to show.
    private(set) var isLive = false

    /// Vorssaint asks for a permission itself, in the pane of the feature that needs it.
    var requiredPermissions: [SonaryPermission] { [] }

    /// False in tests: the module then only keeps its switch, and none of Vorssaint's services,
    /// event taps or menu bar items is started.
    private let drivesEngine: Bool

    init(id: String, title: LocalizedStringResource, symbol: String, drivesEngine: Bool = true) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.drivesEngine = drivesEngine
    }

    func start() async throws {
        if drivesEngine {
            SonaryEngine.setAccent(Color.sonaryAccent)
            SonaryEngine.start(id)
        }
        isLive = true
    }

    func stop() async {
        if drivesEngine { SonaryEngine.stop(id) }
        isLive = false
    }

    /// The settings window draws an engine module with `EnginePage`, not with this.
    func makeSettingsView() -> AnyView { AnyView(EmptyView()) }

    func makePopoverView() -> AnyView? {
        SonaryEngine.setAccent(Color.sonaryAccent)
        return SonaryEngine.panelView(for: id).map { AnyView($0.tint(Color.sonaryAccent)) }
    }

    /// The IDs of the module's settings panes, in order.
    var panes: [String] { SonaryEngine.paneIDs(for: id) }

    /// Shows the module's panes without starting its services, for the snapshot test.
    func installForPreview() {
        SonaryEngine.installForPreview(id)
        isLive = true
    }
}

/// The names of the settings panes inside the engine modules.
enum EnginePaneInfo {
    static func title(_ id: String) -> LocalizedStringKey {
        switch id {
        case "monitor": "Monitor"
        case "panelControls": "Panel"
        case "mouse": "Mouse"
        case "superKey": "Super Key"
        case "keyDebounce": "Key filter"
        case "textSnippets": "Text snippets"
        case "quitProtection": "Quit protection"
        case "notch": "Island"
        case "notchMascot": "Mascot"
        case "clipboard": "History"
        case "cutPaste": "Finder"
        case "shelf": "Shelf"
        case "urlCleaner": "Clean links"
        case "cleaner": "Cleaner"
        case "uninstaller": "Uninstaller"
        case "homebrew": "Homebrew"
        case "appUpdates": "App updates"
        case "autoQuit": "Auto-quit"
        case "killProcess": "Processes"
        case "portManager": "Ports"
        case "windowLayout": "Layouts"
        case "switcher": "App switcher"
        case "dock": "Dock"
        case "brightness": "Brightness"
        case "extraBrightness": "Extra brightness"
        case "mixer": "Mixer"
        case "soundOutput": "Output"
        case "audioPriority": "Device priority"
        case "musicBlocking": "Music app"
        case "keepAwake": "Keep awake"
        case "bluetoothSleep": "Bluetooth"
        case "quickTools": "Quick tools"
        case "screenshot": "Screen capture"
        case "commandBar": "Command bar"
        case "radialMenu": "Radial menu"
        case "media": "Media"
        default: LocalizedStringKey(id)
        }
    }
}
