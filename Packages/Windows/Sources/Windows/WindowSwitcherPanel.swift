import AppKit
import ApplicationServices
import Observation
import ScreenCaptureKit
import SonaryUI
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// What one opening of the switcher shows and where its selection is, shared by the view and
/// by ⌘Tab, which moves the selection from outside while ⌘ is held.
@MainActor
@Observable
final class SwitcherState {
    let entries: [WindowEntry]
    /// The pointer's display, when there is more than one.
    let display: CGRect?
    let style: SwitcherStyle
    var query = ""
    var app: String?
    var onThisDisplay = false
    var selected = 0

    init(entries: [WindowEntry], display: CGRect?, style: SwitcherStyle) {
        self.entries = entries
        self.display = display
        self.style = style
    }

    var results: [WindowEntry] {
        let filtered = filteredEntries(entries, query: query, app: app, display: onThisDisplay ? display : nil)
        return style == .icons ? oneWindowPerApp(filtered) : filtered
    }

    var current: WindowEntry? {
        let list = results
        return list.indices.contains(selected) ? list[selected] : nil
    }

    func move(forward: Bool) {
        selected = nextIndex(from: selected, count: results.count, forward: forward)
    }
}

/// ⌃⌥Tab, or ⌘Tab when the switcher takes it over: every open window, or one icon per app,
/// raising the one you pick.
@MainActor
final class WindowSwitcherController {
    private var panel: SwitcherPanel?
    private var state: SwitcherState?
    /// Live pictures of each window. Off unless the user turns it on, because it needs
    /// the Screen Recording permission.
    var showsPreviews = false
    var style: SwitcherStyle = .list
    /// Told whenever the switcher goes away, so ⌘Tab knows it is closed.
    var onClose: () -> Void = {}

    var isShown: Bool { panel?.isVisible ?? false }

    /// Opens with the keyboard, for searching.
    func show() { present(held: false, forward: true) }

    /// Opens while ⌘ is held, without taking the keyboard from the app in front: the selection
    /// starts on the window behind the front one, or at the far end going backward.
    func showHeld(forward: Bool) { present(held: true, forward: forward) }

    func move(forward: Bool) { state?.move(forward: forward) }

    func chooseSelected() {
        let entry = state?.current
        close()
        if let entry { Self.raise(entry) }
    }

    func close() {
        panel?.orderOut(nil)
        state = nil
        onClose()
    }

    private func present(held: Bool, forward: Bool) {
        let entries = Self.currentEntries()
        guard !entries.isEmpty else {
            close()
            return
        }
        let state = SwitcherState(entries: entries, display: Self.pointerDisplayBounds(), style: style)
        if held { state.selected = heldSelection(count: state.results.count, forward: forward) }
        self.state = state
        if panel == nil {
            let panel = SwitcherPanel(contentRect: CGRect(x: 0, y: 0, width: 560, height: 420),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            // Over full-screen apps too, on whichever Space is showing.
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            self.panel = panel
        }
        guard let panel else { return }
        // While ⌘ is held the app in front keeps the keyboard, so the panel must not hide
        // just because Sonary is not active.
        panel.hidesOnDeactivate = !held
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let size = Self.size(for: state, on: screen)
        panel.contentView = NSHostingView(rootView: WindowSwitcherView(
            state: state,
            showsPreviews: showsPreviews,
            size: size,
            takesKeyboard: !held,
            choose: { [weak self] entry in
                self?.close()
                WindowSwitcherController.raise(entry)
            },
            cancel: { [weak self] in self?.close() }
        ))
        panel.setContentSize(size)
        if let screen {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
        if held {
            panel.orderFrontRegardless()
        } else {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The list keeps one size; the icon row grows with the apps, up to the screen's width.
    private static func size(for state: SwitcherState, on screen: NSScreen?) -> CGSize {
        guard state.style == .icons else { return CGSize(width: 560, height: 420) }
        let widest = (screen?.visibleFrame.width ?? 1200) - 80
        let width = CGFloat(state.results.count) * SwitcherIconRow.slot + 32
        return CGSize(width: min(max(width, 240), widest), height: 150)
    }

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
    @Bindable var state: SwitcherState
    let showsPreviews: Bool
    let size: CGSize
    /// False while ⌘ is held: the keys then come through ⌘Tab, not through the panel.
    let takesKeyboard: Bool
    let choose: (WindowEntry) -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let list = state.results
        Group {
            if state.style == .icons {
                SwitcherIconRow(entries: list, selected: state.selected, choose: choose)
                    .focusable(takesKeyboard)
                    .focusEffectDisabled()
                    .focused($focused)
                    .onKeyPress(.leftArrow) { state.move(forward: false); return .handled }
                    .onKeyPress(.rightArrow) { state.move(forward: true); return .handled }
                    .onKeyPress(.return) { pick(list); return .handled }
            } else {
                windowList(list)
            }
        }
        .padding(16)
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { focused = takesKeyboard }
        .onKeyPress(.downArrow) { state.move(forward: true); return .handled }
        .onKeyPress(.upArrow) { state.move(forward: false); return .handled }
        .onKeyPress(.tab) { state.move(forward: true); return .handled }
        .onKeyPress(.escape) { cancel(); return .handled }
    }

    private func windowList(_ list: [WindowEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $state.query) { Text("Search windows", bundle: .module) }
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($focused)
                .onSubmit { pick(list) }
                .onChange(of: state.query) { _, _ in state.selected = 0 }
            let apps = appNames(in: state.entries)
            if apps.count > 1 || state.display != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if state.display != nil {
                            Button {
                                state.onThisDisplay.toggle()
                                state.selected = 0
                            } label: {
                                Label { Text("This display", bundle: .module) } icon: { Image(systemName: "display") }
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(state.onThisDisplay ? Color.sonaryAccent.opacity(0.28)
                                                    : Color.secondary.opacity(0.14), in: Capsule())
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
            ScrollViewReader { reader in
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
                            .background(index == state.selected ? Color.sonaryAccent.opacity(0.22) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture { choose(entry) }
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: state.selected) { _, index in
                    if list.indices.contains(index) { reader.scrollTo(list[index].id) }
                }
            }
        }
    }

    private func filterChip(title: String, value: String?) -> some View {
        Button {
            state.app = value
            state.selected = 0
        } label: {
            Text(verbatim: title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(state.app == value ? Color.sonaryAccent.opacity(0.28) : Color.secondary.opacity(0.14),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ list: [WindowEntry]) {
        guard list.indices.contains(state.selected) else { return }
        choose(list[state.selected])
    }
}

/// The icon style: one large icon per app in a row, and the selected one's name below.
struct SwitcherIconRow: View {
    /// The width each icon takes, padding included.
    static let slot: CGFloat = 84
    let entries: [WindowEntry]
    let selected: Int
    let choose: (WindowEntry) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            icon(for: entry)
                                .frame(width: 64, height: 64)
                                .padding(8)
                                .background(index == selected ? Color.sonaryAccent.opacity(0.26) : .clear,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { choose(entry) }
                                .accessibilityLabel(Text(verbatim: entry.appName))
                                .accessibilityAddTraits(index == selected ? .isSelected : [])
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: selected) { _, index in
                    if entries.indices.contains(index) { reader.scrollTo(entries[index].id) }
                }
            }
            Text(verbatim: entries.indices.contains(selected) ? entries[selected].label : "")
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func icon(for entry: WindowEntry) -> some View {
        if let image = NSRunningApplication(processIdentifier: entry.pid)?.icon {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app").resizable().aspectRatio(contentMode: .fit).foregroundStyle(.secondary)
        }
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
