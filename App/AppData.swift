import AppKit
import SonaryCore
import UniformTypeIdentifiers

/// Sets of modules to start with, so a new user does not have to pick ten switches.
enum StarterBundle: CaseIterable, Identifiable {
    case essentials, keyboardAndMouse, everything

    var id: Self { self }

    var title: String {
        switch self {
        case .essentials: String(localized: "Essentials")
        case .keyboardAndMouse: String(localized: "Keyboard & mouse")
        case .everything: String(localized: "Everything")
        }
    }

    var moduleIDs: [String] {
        switch self {
        case .essentials: ["monitor", "windows", "clipboard", "tools"]
        case .keyboardAndMouse: ["mouse", "keyboard", "windows"]
        case .everything: ModuleCategory.allCases.flatMap(\.moduleIDs)
        }
    }
}

/// Settings keys that belong to the updater or to AppKit, not to Sonary's own choices. The
/// clipboard history (kept in UserDefaults before 0.83.5) is data, not a setting, and stays out
/// of exported settings files.
func isTransferableSettingsKey(_ key: String) -> Bool {
    !key.hasPrefix("SU") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple.") && key != "app.lastVersion"
        && key != "clipboard.history"
}

extension AppModel {
    /// Turns on every module of a bundle; modules already on stay on.
    func apply(_ bundle: StarterBundle) async {
        for id in bundle.moduleIDs where !registry.isEnabled(id) {
            await registry.setEnabled(id, true)
        }
    }

    /// Writes Sonary's settings to a file the user picks, to move them to another Mac.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sonary Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url,
              let domain = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) else { return }
        let kept = domain.filter { isTransferableSettingsKey($0.key) }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: kept, format: .xml, options: 0) else { return }
        try? data.write(to: url)
    }

    /// Reads settings written by `exportSettings` and restarts Sonary with them.
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        Task {
            await stopEverything()
            for (key, value) in values where isTransferableSettingsKey(key) {
                defaults.set(value, forKey: key)
            }
            relaunch()
        }
    }

    /// Stops every module, so the system gets back what Sonary changed, then removes all of
    /// Sonary's settings and its data folder and quits. Scripts the user wrote stay.
    func removeAllData() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove all of Sonary's data?")
        alert.informativeText = String(localized: "Settings, the clipboard history and everything else Sonary keeps are deleted, and Sonary quits. Your scripts folder stays.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Remove and quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await stopEverything()
            if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let folder = support.appendingPathComponent("Sonary", isDirectory: true)
                let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                for item in items where item.lastPathComponent != "Scripts" {
                    try? FileManager.default.removeItem(at: item)
                }
            }
            NSApp.terminate(nil)
        }
    }

    private func stopEverything() async {
        for module in registry.modules where registry.isEnabled(module.id) {
            // Stopping through the registry would also store "off" for each module.
            await module.stop()
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { @Sendable _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Opens the menu bar panel, for the shortcut. The panel belongs to the status item
    /// SwiftUI made, which is found by its window.
    func openPanel() {
        let statusWindow = NSApp.windows.first { $0.className.contains("NSStatusBarWindow") }
        let button = statusWindow?.contentView.flatMap(Self.statusButton(in:))
        button?.performClick(nil)
    }

    /// Closes the menu bar panel if it is open, for actions that need the screen to themselves.
    func closePanelIfOpen() {
        let isOpen = NSApp.windows.contains { $0.isVisible && $0.className.contains("MenuBarExtra") }
        if isOpen { openPanel() }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = statusButton(in: subview) { return found }
        }
        return nil
    }

    /// The panel shortcut, on the shortcut page with the others.
    func registerPanelShortcut() {
        let store = ShortcutStore.shared
        store.describe([ShortcutDefinition(id: "app.panel", title: String(localized: "Open the menu panel"),
                                           group: "Sonary", defaultCombo: KeyCombo.none)])
        store.bind("app.panel") { [weak self] in self?.openPanel() }
    }

    /// Every option text of the running language, by module, for the settings search.
    func searchableOptions() -> [(moduleID: String, text: String)] {
        registry.modules.flatMap { module -> [(moduleID: String, text: String)] in
            guard let bundle = module.resourceBundle,
                  let path = bundle.path(forResource: "Localizable", ofType: "strings"),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else { return [] }
            return searchableTexts(table).map { (module.id, $0) }
        }
    }
}

/// The list with the entry at `index` swapped with the one above it.
func movedUp(_ ids: [String], at index: Int) -> [String] {
    guard index > 0, ids.indices.contains(index) else { return ids }
    var result = ids
    result.swapAt(index, index - 1)
    return result
}

/// What the menu panel shows besides the modules.
struct PanelOptions: Codable, Equatable, Sendable {
    /// The time and date in the header.
    var showsClock = true
    /// Seconds on the clock.
    var clockSeconds = false
    /// The live values at the top of the overview.
    var showsGlance = true
    /// Two or three tiles to a row.
    var glanceColumns = 2
    /// How many tiles at most.
    var glanceLimit = 8
    /// Live values left out of the overview, as "module.value".
    var hiddenGlance: [String] = []
    /// A second line with live values under each running module.
    var showsStatusLines = true
}

/// The key a live value is hidden under.
func glanceKey(_ moduleID: String, _ statusID: String) -> String { moduleID + "." + statusID }
