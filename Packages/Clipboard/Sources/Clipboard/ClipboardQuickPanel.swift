import AppKit
import SonaryUI
import SwiftUI

final class ClipboardQuickWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌃⌥V: the clipboard history in a floating panel with search and a preview, pasting the
/// entry you pick into the app you came from.
@MainActor
final class ClipboardQuickPanel {
    private var panel: ClipboardQuickWindow?
    /// The app in front before the panel opened, which gets the paste.
    private var previousApp: NSRunningApplication?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(model: ClipboardModel) {
        if isShown { close() } else { show(model: model) }
    }

    func show(model: ClipboardModel) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if panel == nil {
            let panel = ClipboardQuickWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 420),
                                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                             defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            self.panel = panel
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: ClipboardQuickView(
            model: model,
            choose: { [weak self] entry in self?.choose(entry, model: model) },
            cancel: { [weak self] in self?.close() }
        ))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - 340, y: screen.frame.midY - 210))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func choose(_ entry: ClipboardEntry, model: ClipboardModel) {
        close()
        model.copy(entry)
        guard model.settings.quickPanelPastes else { return }
        let target = previousApp
        Task { @MainActor in
            target?.activate()
            // Give the app a moment to come forward before the paste arrives.
            try? await Task.sleep(for: .milliseconds(180))
            ClipboardModel.pressCommandV()
        }
    }
}

struct ClipboardQuickView: View {
    let model: ClipboardModel
    let choose: (ClipboardEntry) -> Void
    let cancel: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let entries = model.history.search(query)
        let current = entries.indices.contains(selected) ? entries[selected] : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text: $query) { Text("Search the clipboard", bundle: .module) }
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit { if let current { choose(current) } }
                    .onChange(of: query) { _, _ in selected = 0 }
            }
            Divider()
            if entries.isEmpty {
                Text("Nothing copied yet, or nothing matches.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    list(entries)
                        .frame(width: 280)
                    Divider()
                    ClipboardEntryPreview(model: model, entry: current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            (model.settings.quickPanelPastes
                ? Text("Return or ⌘1–9 pastes, Esc closes", bundle: .module)
                : Text("Return or ⌘1–9 copies, Esc closes", bundle: .module))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 680, height: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selected = step(selected, count: entries.count, by: 1); return .handled }
        .onKeyPress(.upArrow) { selected = step(selected, count: entries.count, by: -1); return .handled }
        .onKeyPress(.escape) { cancel(); return .handled }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.contains(.command),
                  let index = quickPasteIndex(press.characters), entries.indices.contains(index) else { return .ignored }
            choose(entries[index])
            return .handled
        }
    }

    private func list(_ entries: [ClipboardEntry]) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            ClipboardEntryIcon(model: model, entry: entry)
                            Text(verbatim: entry.searchText.replacingOccurrences(of: "\n", with: " "))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if entry.isPinned {
                                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                            }
                            if index < 9 {
                                Text(verbatim: "⌘\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(index == selected ? Color.sonaryAccent.opacity(0.22) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { choose(entry) }
                        .id(entry.id)
                    }
                }
            }
            .onChange(of: selected) { _, index in
                if entries.indices.contains(index) { reader.scrollTo(entries[index].id) }
            }
        }
    }

    private func step(_ index: Int, count: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }
}

/// The whole of one entry: all of its text, the image at full width, or every file.
struct ClipboardEntryPreview: View {
    let model: ClipboardModel
    let entry: ClipboardEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let entry {
                content(entry)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let app = entry.sourceApp, let name = appName(app) {
                        Text(verbatim: name)
                        Text(verbatim: "·")
                    }
                    Text(entry.copiedAt, style: .relative)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ entry: ClipboardEntry) -> some View {
        switch entry.content {
        case let .text(value):
            ScrollView {
                Text(verbatim: previewText(value))
                    .font(.system(size: 12, design: looksLikeCode(value) ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("\(value.count) characters", bundle: .module).font(.caption).foregroundStyle(.secondary)
        case .image:
            if let url = model.imageURL(for: entry), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(verbatim: "\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case let .files(paths):
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 22, height: 22)
                            Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12)).lineLimit(2).truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func appName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// A thumbnail for images, an icon for files, a text symbol for text.
struct ClipboardEntryIcon: View {
    let model: ClipboardModel
    let entry: ClipboardEntry

    var body: some View {
        Group {
            switch entry.content {
            case .text:
                Image(systemName: "text.alignleft").foregroundStyle(.secondary)
            case .image:
                if let url = model.imageURL(for: entry), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            case let .files(paths):
                if let first = paths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable()
                }
            }
        }
        .frame(width: 20, height: 20)
    }
}
