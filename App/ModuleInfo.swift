import SwiftUI

/// One-line descriptions of the modules, shown in Settings and the menu panel.
enum ModuleInfo {
    static func summary(for id: String) -> LocalizedStringKey {
        switch id {
        case "monitor": "CPU, GPU, memory, network, disk, battery and temperatures, with history and alerts."
        case "mouse": "Linear or smooth scrolling, pointer acceleration, extra buttons, click filter and app exceptions."
        case "notch": "An island at the notch with music, calendar, timer, downloads and accessory batteries."
        case "clipboard": "Clipboard history, clean links, plain-text paste, a file shelf and Finder helpers."
        case "apps": "Cleaner, uninstaller, quit and force quit, port manager and Homebrew updates."
        default: ""
        }
    }
}
