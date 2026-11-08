import SwiftUI

/// The pages of the settings window. The panel opens a module's page by setting
/// `AppModel.settingsPage` before it opens the window. (`SettingsPage` is SonaryUI's page container.)
enum SettingsDestination: Hashable {
    case general
    case features
    case permissions
    case shortcuts
    case updates
    case about
    case module(String)
}

/// The tabs of the menu bar panel: the module overview, then one per running module.
enum PanelTab: Hashable {
    case overview
    case module(String)
}

/// The groups modules are listed in, in the panel's overview and in the settings sidebar.
enum ModuleCategory: CaseIterable, Hashable {
    case system
    case input
    case windows
    case files

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .input: "Mouse & keyboard"
        case .windows: "Windows"
        case .files: "Files & tools"
        }
    }

    /// The badge of the category's foldable section in the panel's overview.
    var symbol: String {
        switch self {
        case .system: "cpu"
        case .input: "computermouse"
        case .windows: "macwindow"
        case .files: "folder"
        }
    }

    /// The key the panel remembers the open section by.
    var storageID: String {
        switch self {
        case .system: "system"
        case .input: "input"
        case .windows: "windows"
        case .files: "files"
        }
    }

    var moduleIDs: [String] {
        switch self {
        case .system: ["monitor", "display", "sound", "awake"]
        case .input: ["mouse", "keyboard"]
        case .windows: ["windows", "notch"]
        case .files: ["clipboard", "apps", "tools"]
        }
    }
}
