import AppKit
import ApplicationServices
import SonaryUI
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌃⌥Tab: a list of every open window, with search, that raises the one you pick.
@MainActor
final class WindowSwitcherController {
    private var panel: SwitcherPanel?

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
    let choose: (WindowEntry) -> Void
    let cancel: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [WindowEntry] { filteredEntries(entries, query: query) }

    var body: some View {
        let list = results
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query) { Text("Search windows", bundle: .module) }
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($focused)
                .onSubmit { pick(list) }
                .onChange(of: query) { _, _ in selected = 0 }
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

    private func pick(_ list: [WindowEntry]) {
        guard list.indices.contains(selected) else { return }
        choose(list[selected])
    }
}
