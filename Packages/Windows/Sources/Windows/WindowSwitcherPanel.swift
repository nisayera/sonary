import AppKit
import ApplicationServices
import ScreenCaptureKit
import SonaryUI
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌃⌥Tab: a list of every open window, with search, that raises the one you pick.
@MainActor
final class WindowSwitcherController {
    private var panel: SwitcherPanel?
    /// Live pictures of each window. Off unless the user turns it on, because it needs
    /// the Screen Recording permission.
    var showsPreviews = false

    func show() {
        let entries = Self.currentEntries()
        guard !entries.isEmpty else { return }
        if panel == nil {
            let panel = SwitcherPanel(contentRect: CGRect(x: 0, y: 0, width: 560, height: 420),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hidesOnDeactivate = true
            self.panel = panel
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: WindowSwitcherView(
            entries: entries,
            showsPreviews: showsPreviews,
            display: Self.pointerDisplayBounds(),
            choose: { [weak self] entry in
                self?.close()
                WindowSwitcherController.raise(entry)
            },
            cancel: { [weak self] in self?.close() }
        ))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - 280, y: screen.frame.midY - 210))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    /// The display the pointer is on, in window-server coordinates, for the "this display"
    /// filter. Nil with a single display, where the filter would change nothing.
    static func pointerDisplayBounds() -> CGRect? {
        guard NSScreen.screens.count > 1 else { return nil }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDisplayBounds(number.uint32Value)
    }

    static func currentEntries() -> [WindowEntry] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let windows = (raw as? [[String: Any]]) ?? []
        return switcherEntries(from: windows, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// Brings the app forward and raises that window, matched by its title.
    static func raise(_ entry: WindowEntry) {
        NSRunningApplication(processIdentifier: entry.pid)?.activate()
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(entry.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        let match = windows.first { window in
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else { return false }
            return title == entry.title
        } ?? windows.first
        guard let match else { return }
        AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}

struct WindowSwitcherView: View {
    let entries: [WindowEntry]
    let showsPreviews: Bool
    /// The pointer's display, when there is more than one.
    let display: CGRect?
    let choose: (WindowEntry) -> Void
    let cancel: () -> Void
    @State private var query = ""
    @State private var app: String?
    @State private var onThisDisplay = false
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [WindowEntry] {
        filteredEntries(entries, query: query, app: app, display: onThisDisplay ? display : nil)
    }

    var body: some View {
        let list = results
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query) { Text("Search windows", bundle: .module) }
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($focused)
                .onSubmit { pick(list) }
                .onChange(of: query) { _, _ in selected = 0 }
            let apps = appNames(in: entries)
            if apps.count > 1 || display != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if display != nil {
                            Button {
                                onThisDisplay.toggle()
                                selected = 0
                            } label: {
                                Label { Text("This display", bundle: .module) } icon: { Image(systemName: "display") }
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(onThisDisplay ? Color.sonaryAccent.opacity(0.28) : Color.secondary.opacity(0.14),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        filterChip(title: String(localized: "All apps", bundle: .module), value: nil)
                        ForEach(apps, id: \.self) { name in filterChip(title: name, value: name) }
                    }
                }
                .frame(height: 26)
            }
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            if let icon = NSRunningApplication(processIdentifier: entry.pid)?.icon {
                                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                            }
                            Text(entry.label).lineLimit(1)
                            Spacer()
                            if showsPreviews {
                                WindowPreviewImage(id: entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(index == selected ? Color.sonaryAccent.opacity(0.22) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { choose(entry) }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selected = nextIndex(from: selected, count: list.count, forward: true); return .handled }
        .onKeyPress(.upArrow) { selected = nextIndex(from: selected, count: list.count, forward: false); return .handled }
        .onKeyPress(.tab) { selected = nextIndex(from: selected, count: list.count, forward: true); return .handled }
        .onKeyPress(.escape) { cancel(); return .handled }
    }

    private func filterChip(title: String, value: String?) -> some View {
        Button {
            app = value
            selected = 0
        } label: {
            Text(verbatim: title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(app == value ? Color.sonaryAccent.opacity(0.28) : Color.secondary.opacity(0.14),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ list: [WindowEntry]) {
        guard list.indices.contains(selected) else { return }
        choose(list[selected])
    }
}

/// The rectangle shown while a window is dragged against an edge.
struct SnapPreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.sonaryAccent.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.sonaryAccent, lineWidth: 2)
            )
            .padding(6)
    }
}

/// A picture of one window, fetched once and kept for a few seconds. Nil without the
/// Screen Recording permission, which is why previews are a setting rather than the default.
@MainActor
enum WindowPreviews {
    private static var cache: [UInt32: (image: NSImage, taken: Date)] = [:]

    static func image(for id: UInt32) async -> NSImage? {
        if let hit = cache[id], Date().timeIntervalSince(hit.taken) < 5 { return hit.image }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == id }),
              window.frame.width > 1, window.frame.height > 1 else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        configuration.showsCursor = false
        guard let shot = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        else { return nil }
        let image = NSImage(cgImage: shot, size: NSSize(width: shot.width, height: shot.height))
        cache[id] = (image, Date())
        return image
    }
}

/// The thumbnail in a switcher row. It stays empty until the picture arrives, so the
/// list never waits on the capture.
struct WindowPreviewImage: View {
    let id: UInt32
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Color.clear
            }
        }
        .frame(width: 92, height: 56)
        .accessibilityHidden(true)
        .task(id: id) { image = await WindowPreviews.image(for: id) }
    }
}
