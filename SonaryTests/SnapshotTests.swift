import AppKit
import SonaryCore
import SwiftUI
import Testing
@testable import Sonary

/// Renders the menu bar panel and the settings window to PNG files, so a change to the interface
/// can be looked at without running the app. Only when SONARY_SNAPSHOT_DIR names a folder (CI
/// sets it); otherwise the test does nothing.
@MainActor
struct SnapshotTests {
    @Test func panelAndSettings() async throws {
        guard let path = ProcessInfo.processInfo.environment["SONARY_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let defaults = try #require(UserDefaults(suiteName: "sonary.snapshots.\(UUID().uuidString)"))
        let model = AppModel(defaults: defaults, startUpdater: false)
        // Modules that need no permission can run on CI; the others show as off.
        let running = ["monitor", "clipboard", "apps", "display", "sound", "tools"]
        for id in running {
            await model.registry.setEnabled(id, true)
        }
        try await Task.sleep(for: .seconds(4))  // a few monitor samples

        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            await render(PopoverView(model: model), name: "panel-overview-\(suffix)", scheme: scheme, in: folder)
            for id in running {
                await render(PopoverView(model: model, initialTab: .module(id)), name: "panel-\(id)-\(suffix)",
                             scheme: scheme, in: folder)
            }
        }

        let pages: [(SettingsDestination, String)] = [
            (.general, "general"), (.features, "features"), (.permissions, "permissions"),
            (.shortcuts, "shortcuts"), (.module("mouse"), "mouse"), (.module("windows"), "windows"),
            (.module("monitor"), "monitor"),
        ]
        for (page, name) in pages {
            model.settingsPage = page
            await render(SettingsView(model: model).frame(width: 900, height: 620), name: "settings-\(name)",
                         scheme: .dark, in: folder)
        }

        for id in running {
            await model.registry.setEnabled(id, false)
        }
    }

    /// Lays the view out in an off-screen window, lets it settle, and writes what it draws.
    private func render(_ view: some View, name: String, scheme: ColorScheme, in folder: URL) async {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            window.setContentSize(NSSize(width: max(size.width, 100), height: max(size.height, 100)))
            try? await Task.sleep(for: .milliseconds(400))
        }
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let file = folder.appendingPathComponent("\(name).png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
        window.close()
    }
}
