import Foundation
import SonaryCore
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

/// The name System Settings uses for a permission, in the user's language.
func permissionTitle(_ permission: SonaryPermission) -> String {
    switch permission {
    case .accessibility: String(localized: "Accessibility")
    case .inputMonitoring: String(localized: "Input Monitoring")
    case .screenRecording: String(localized: "Screen Recording")
    case .fullDiskAccess: String(localized: "Full Disk Access")
    case .notifications: String(localized: "Notifications")
    case .calendars: String(localized: "Calendars")
    }
}

/// "Accessibility and Screen Recording", for sentences that name several permissions.
func permissionList(_ permissions: [SonaryPermission]) -> String {
    ListFormatter.localizedString(byJoining: permissions.map(permissionTitle))
}

/// What the settings show when a module could not start for lack of a permission.
@MainActor
func missingPermissionText(_ permissions: [SonaryPermission]) -> String {
    let names = permissionList(permissions)
    return String(localized: "Sonary needs \(names) for this module. Allow it under System Settings → Privacy & Security, then turn the module on again.")
}
