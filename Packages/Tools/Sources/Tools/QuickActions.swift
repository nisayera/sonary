import AppKit
import Foundation

public enum QuickAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case darkMode, desktopIcons, emptyTrash, ejectDisks, lockScreen
    case commandBar, textFromScreen, colorPicker, screenshot

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .darkMode: "circle.lefthalf.filled"
        case .desktopIcons: "macwindow.on.rectangle"
        case .emptyTrash: "trash"
        case .ejectDisks: "eject"
        case .lockScreen: "lock.display"
        case .commandBar: "magnifyingglass"
        case .textFromScreen: "text.viewfinder"
        case .colorPicker: "eyedropper"
        case .screenshot: "camera.viewfinder"
        }
    }
}

/// The system actions, kept apart from the model so the UI list and the radial menu agree.
public let quickToggleActions: [QuickAction] = [.darkMode, .desktopIcons, .emptyTrash, .ejectDisks, .lockScreen]

enum SystemActions {
    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    static func toggleDarkMode() {
        runAppleScript("""
        tell application "System Events" to tell appearance preferences
            set dark mode to not dark mode
        end tell
        """)
    }

    static func toggleDesktopIcons() {
        let defaults = UserDefaults(suiteName: "com.apple.finder")
        let shown = defaults?.object(forKey: "CreateDesktop") as? Bool ?? true
        defaults?.set(!shown, forKey: "CreateDesktop")
        run("/usr/bin/killall", ["Finder"])
    }

    static func emptyTrash() {
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    static func ejectDisks() {
        runAppleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")
    }

    static func lockScreen() {
        run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}
