import AppKit
import SonaryUI
import SwiftUI
import UniformTypeIdentifiers

private enum ClipboardSection: String, CaseIterable, Identifiable {
    case history, shelf, finder
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .history: "History"
        case .shelf: "Shelf"
        case .finder: "Finder"
        }
    }
}

struct ClipboardPopoverView: View {
    let model: ClipboardModel
    @State private var section: ClipboardSection = .history
    @State private var query = ""
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(selection: $section) {
                ForEach(ClipboardSection.allCases) { Text($0.title, bundle: .module).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
            switch section {
            case .history: historyView
            case .shelf: shelfView
            case .finder: finderView
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $query) { Text("Search", bundle: .module) }
                .textFieldStyle(.roundedBorder)
            let entries = model.history.search(query)
            if entries.isEmpty {
                Text("Copied text appears here.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, Spacing.s)
            }
            if !entries.isEmpty {
                PanelGroup {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Button { model.copy(entry) } label: {
                                HStack(spacing: 8) {
                                    preview(for: entry)
                                    Text(entry.searchText.replacingOccurrences(of: "\n", with: " "))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(Text("Copy again", bundle: .module))
                            Button { model.togglePin(entry) } label: {
                                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(entry.isPinned ? Text("Unpin", bundle: .module) : Text("Pin", bundle: .module))
                            Button { model.remove(entry) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Remove", bundle: .module))
                        }
                        .font(.system(size: 12))
                        .panelRowInsets()
                    }
                }
            }
            if !model.history.entries.isEmpty {
                Button(role: .destructive) { model.clearHistory() } label: {
                    Text("Clear history (keeps pinned)", bundle: .module)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// A thumbnail for images, an icon for files, nothing for plain text.
    @ViewBuilder
    private func preview(for entry: ClipboardEntry) -> some View {
        switch entry.content {
        case .text:
            EmptyView()
        case .image:
            if let url = model.imageURL(for: entry), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 26).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        case let .files(paths):
            if let first = paths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable().frame(width: 20, height: 20)
            }
        }
    }

    private var shelfView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(dropTargeted ? Color.sonaryAccent : Color.secondary.opacity(0.5))
                Text("Drop files here to keep them handy", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(height: 70)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in model.addToShelf([url]) }
                    }
                }
                return true
            }
            if !model.shelf.isEmpty {
                PanelGroup {
                    ForEach(model.shelf, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.removeFromShelf(url) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Remove", bundle: .module))
                        }
                        .font(.system(size: 12))
                        .panelRowInsets()
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    }
                }
            }
            if !model.shelf.isEmpty {
                Text("Drag files out of the shelf to move or copy them.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var finderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelGroup {
                Group {
                    Button { model.copyFinderSelectionPaths() } label: {
                        Label { Text("Copy path of selected items", bundle: .module) } icon: { Image(systemName: "doc.on.clipboard") }
                    }
                    Button { model.openTerminalInFinderFolder() } label: {
                        Label { Text("Open Terminal in current folder", bundle: .module) } icon: { Image(systemName: "terminal") }
                    }
                    Button { model.newTextFileInFinderFolder() } label: {
                        Label { Text("New text file in current folder", bundle: .module) } icon: { Image(systemName: "doc.badge.plus") }
                    }
                    Button { model.cutFinderSelection() } label: {
                        Label { Text("Cut the selected files", bundle: .module) } icon: { Image(systemName: "scissors") }
                    }
                    Button { model.pasteCutFiles() } label: {
                        Label { Text("Move them into this folder", bundle: .module) } icon: { Image(systemName: "arrow.right.doc.on.clipboard") }
                    }
                    .disabled(model.cutFiles.isEmpty)
                    Button { model.renameFinderSelection() } label: {
                        Label { Text("Rename the selected file", bundle: .module) } icon: { Image(systemName: "pencil") }
                    }
                    Button { model.saveClipboardImageToFinderFolder() } label: {
                        Label { Text("Save clipboard image here as PNG", bundle: .module) } icon: { Image(systemName: "photo.badge.arrow.down") }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12))
                .panelRowInsets()
            }
            if let message = model.lastMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }
}

struct ClipboardSettingsView: View {
    let model: ClipboardModel

    var body: some View {
        SettingsCard(Text("History", bundle: .module)) {
            SettingsRow(symbol: "clock.arrow.circlepath",
                        title: Text("Keep the last \(model.settings.historyLimit) copies", bundle: .module),
                        caption: Text("Pinned entries are always kept. Passwords from password managers are never recorded.",
                                      bundle: .module)) {
                Stepper(value: Binding(get: { model.settings.historyLimit },
                                       set: { value in model.update { $0.historyLimit = value } }),
                        in: 10...500, step: 10) { EmptyView() }
                    .labelsHidden()
            }
        }
        SettingsCard(Text("What is recorded", bundle: .module)) {
            SettingsToggleRow(symbol: "photo", title: Text("Images", bundle: .module),
                              caption: Text("Copied images are kept as files and opened again from the list.", bundle: .module),
                              isOn: Binding(get: { model.settings.captureImages },
                                            set: { value in model.update { $0.captureImages = value } }))
            SettingsToggleRow(symbol: "doc", title: Text("Files", bundle: .module),
                              isOn: Binding(get: { model.settings.captureFiles },
                                            set: { value in model.update { $0.captureFiles = value } }))
        }
        SettingsCard(Text("Clearing", bundle: .module)) {
            SettingsRow(symbol: "clock.badge.xmark",
                        title: model.settings.autoClearMinutes == 0
                            ? Text("Keep entries until I clear them", bundle: .module)
                            : Text("Forget entries after \(model.settings.autoClearMinutes) minutes", bundle: .module),
                        caption: Text("Pinned entries always stay.", bundle: .module)) {
                Stepper(value: Binding(get: { model.settings.autoClearMinutes },
                                       set: { value in model.update { $0.autoClearMinutes = value } }),
                        in: 0...240, step: 15) { EmptyView() }
                    .labelsHidden()
            }
            SettingsToggleRow(symbol: "moon.zzz", title: Text("Clear when the Mac goes to sleep", bundle: .module),
                              isOn: Binding(get: { model.settings.clearOnSleep },
                                            set: { value in model.update { $0.clearOnSleep = value } }))
            SettingsToggleRow(symbol: "lock", title: Text("Clear when the screen locks", bundle: .module),
                              isOn: Binding(get: { model.settings.clearOnLock },
                                            set: { value in model.update { $0.clearOnLock = value } }))
        }
        SettingsCard(Text("Copying and pasting", bundle: .module)) {
            SettingsToggleRow(symbol: "link", title: Text("Clean links", bundle: .module),
                              caption: Text("Removes tracking parameters such as utm_source or fbclid from copied links.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.cleanLinks },
                                            set: { value in model.update { $0.cleanLinks = value } }))
            SettingsToggleRow(symbol: "textformat", title: Text("Paste as plain text with ⌘⌥⇧V", bundle: .module),
                              caption: Text("Strips formatting, pastes, and puts the original contents back. Needs the Accessibility permission.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.plainTextPasteShortcut },
                                            set: { value in model.update { $0.plainTextPasteShortcut = value } }))
        }
        SettingsCard(Text("Shelf and Finder", bundle: .module)) {
            Text("Open the menu panel's clipboard tab to use the file shelf and the Finder helpers. The Finder helpers ask once for permission to control Finder.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
