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
        case "windows": "Window layouts on ⌃⌥ shortcuts and protection against quitting apps by accident."
        case "sound": "Switch speakers and microphones, volume, microphone mute on ⌃⌥M and keep awake."
        case "tools": "Command bar, text from screen, color picker, screenshots, scratchpad and snippets."
        case "keyboard": "Super Key: one key becomes ⌃⌥⇧⌘ while held and runs an action when tapped."
        case "display": "Brightness for every display, with shortcuts and dimming for displays without hardware control."
        default: ""
        }
    }
}
