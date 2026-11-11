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
    @Test(.timeLimit(.minutes(5)))
    func panelAndSettings() async throws {
        guard let path = ProcessInfo.processInfo.environment["SONARY_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let defaults = try #require(UserDefaults(suiteName: "sonary.snapshots.\(UUID().uuidString)"))
        let model = AppModel(defaults: defaults, startUpdater: false)
        // Modules that need no permission and no audio or display hardware can run on CI (a CI
        // machine has no microphone, and Core Audio and display services can stall there).
        // The engine modules are Vorssaint's services and are not started here; their panes and
        // panel sections are drawn with the features marked as installed.
        let running: [String] = []
        let previewed = ["monitor", "mouse", "keyboard", "notch", "clipboard", "windows", "awake", "tools"]
        for id in previewed {
            (model.registry.modules.first { $0.id == id } as? EngineModule)?.installForPreview()
        }
        for id in running {
            print("SNAPSHOT starting \(id)")
            await model.registry.setEnabled(id, true)
        }
        try await Task.sleep(for: .seconds(4))  // a few monitor samples
        print("SNAPSHOT modules running")

        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            await render(PopoverView(model: model), name: "panel-overview-\(suffix)", scheme: scheme, in: folder)
            for id in running {
                await render(PopoverView(model: model, initialTab: .module(id)), name: "panel-\(id)-\(suffix)",
                             scheme: scheme, in: folder)
            }
        }

        // Tabs of modules that cannot run on CI are drawn on their own, on the panel's surface.
        // Only the ones whose view touches no hardware when it appears.
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for id in ["awake", "tools"] {
                if let view = model.registry.modules.first(where: { $0.id == id })?.makePopoverView() {
                    await render(PanelTabPreview(content: view), name: "panel-\(id)-\(suffix)", scheme: scheme, in: folder)
                }
            }
        }

        let pages: [(SettingsDestination, String)] = [
            (.general, "general"), (.features, "features"), (.permissions, "permissions"),
            (.shortcuts, "shortcuts"), (.module("mouse"), "mouse"), (.module("windows"), "windows"),
            (.module("monitor"), "monitor"), (.module("tools"), "tools"), (.module("clipboard"), "clipboard"),
            (.module("awake"), "awake"), (.module("keyboard"), "keyboard"),
            (.module("notch"), "notch"), (.about, "about"),
        ]
        // The settings window's materials are not drawn off screen, so the page gets the window's
        // own colour behind it, or its text would stand on nothing.
        for (page, name) in pages {
            model.settingsPage = page
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .dark ? "dark" : "light"
                await render(SettingsView(model: model)
                                .frame(width: 900, height: 620)
                                .background(Color(nsColor: .windowBackgroundColor)),
                             name: "settings-\(name)-\(suffix)", scheme: scheme, in: folder)
            }
        }

        for id in running {
            await model.registry.setEnabled(id, false)
        }
    }

    /// Lays the view out in an off-screen window, lets it settle, and writes what it draws.
    private func render(_ view: some View, name: String, scheme: ColorScheme, in folder: URL) async {
        print("SNAPSHOT rendering \(name)")
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
