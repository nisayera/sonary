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

/// The tabs of the menu bar panel: Home, then one per area that has something running.
/// `.module` carries a `PanelArea`'s id.
enum PanelTab: Hashable {
    case overview
    case module(String)
}

/// The areas of the menu bar panel after Home, in their default order. An area gathers the
/// sections of several modules by what they are about, not by the module they come from.
enum PanelArea: String, CaseIterable {
    case system, network, disks, energy, utilities, control, quick

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .network: "Network"
        case .disks: "Disks"
        case .energy: "Energy"
        case .utilities: "Utilities"
        case .control: "Control"
        case .quick: "Quick actions"
        }
    }

    var symbol: String {
        switch self {
        case .system: "cpu"
        case .network: "network"
        case .disks: "internaldrive"
        case .energy: "bolt.fill"
        case .utilities: "wrench.and.screwdriver"
        case .control: "computermouse"
        case .quick: "star.fill"
        }
    }

    /// The modules whose sections the area shows. The tab appears while one of them runs.
    var moduleIDs: [String] {
        switch self {
        case .system: ["monitor", "display", "sound", "awake"]
        case .network: ["monitor", "apps"]
        case .disks, .energy: ["monitor"]
        case .utilities: ["tools", "apps", "clipboard", "windows"]
        case .control: ["mouse", "keyboard", "windows", "clipboard", "apps"]
        case .quick: ["tools"]
        }
    }

    /// The settings page behind the area's settings button.
    var settingsModule: String {
        switch self {
        case .system, .network, .disks, .energy: "monitor"
        case .utilities, .quick: "tools"
        case .control: "mouse"
        }
    }
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
