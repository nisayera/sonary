import AppKit
import SonaryUI
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardPopoverView: View {
    let model: ClipboardModel
    /// The section that is open; one at a time, so the panel stays short and never scrolls.
    @AppStorage("panel.clipboard.open") private var open = "history"
    @State private var query = ""
    @State private var dropTargeted = false
    @State private var linkToClean = ""
    @State private var showsAllHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDisclosure(symbol: "doc.on.clipboard", title: Text("History", bundle: .module),
                            isExpanded: $open.opens("history")) {
                Text(verbatim: "\(model.history.entries.count)")
            } content: {
                historyView
            }
            PanelDisclosure(symbol: "tray", title: Text("Shelf", bundle: .module),
                            isExpanded: $open.opens("shelf")) {
                if !model.shelf.isEmpty { Text(verbatim: "\(model.shelf.count)") }
            } content: {
                shelfView
            }
            PanelDisclosure(symbol: "folder", title: Text("Finder", bundle: .module),
                            isExpanded: $open.opens("finder")) {
                finderView
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $query) { Text("Search", bundle: .module) }
                .textFieldStyle(.roundedBorder)
            let entries = model.history.search(query)
            if entries.isEmpty {
                PanelEmptyState(symbol: "doc.on.clipboard", text: Text("Copied text appears here.", bundle: .module))
            }
            if !entries.isEmpty {
                PanelGroup {
                    ForEach(PanelListLimit.visible(entries, showsAll: showsAllHistory)) { entry in
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
            if PanelListLimit.isLong(entries.count) {
                PanelMoreButton(showsAll: $showsAllHistory, more: Text("Show all (\(entries.count))", bundle: .module),
                                less: Text("Show less", bundle: .module))
            }
            if !model.history.entries.isEmpty {
                Button(role: .destructive) { model.clearHistory() } label: {
                    Text("Clear history (keeps pinned)", bundle: .module)
                }
                .buttonStyle(.borderless)
            }
            cleanLinkRow
        }
    }

    /// Paste a link, get it back without its tracking parameters.
    private var cleanLinkRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField(text: $linkToClean) { Text("Paste a link to clean", bundle: .module) }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { copyCleanLink() }
                Button { copyCleanLink() } label: { Text("Copy clean", bundle: .module) }
                    .disabled(linkToClean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let trimmed = linkToClean.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let clean = model.cleanLink(trimmed)
                Text(verbatim: clean)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                if clean == trimmed {
                    Text("Nothing to remove from this one.", bundle: .module).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func copyCleanLink() {
        guard !linkToClean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.copyCleanLink(linkToClean)
        linkToClean = ""
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
                Text("Drop files, text or links here to keep them handy", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .frame(height: 70)
            .onDrop(of: shelfDropTypes, isTargeted: $dropTargeted) { providers in
                loadShelfItems(from: providers) { model.addToShelf($0) }
                return true
            }
            if !model.shelf.isEmpty {
                PanelGroup {
                    ForEach(model.shelf) { item in
                        ShelfItemRow(item: item) { model.removeFromShelf(item) }
                            .panelRowInsets()
                    }
                }
                Text("Drag things out of the shelf to move or copy them, or share them.", bundle: .module)
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
        SettingsCard(Text("Quick panel", bundle: .module)) {
            SettingsRow(symbol: "list.clipboard", title: Text("Clipboard history on ⌃⌥V", bundle: .module),
                        caption: Text("Search everything you copied, see each entry in full, and pick one with Return or ⌘1 to ⌘9. Change the shortcut on the Shortcuts page.",
                                      bundle: .module)) {
                Button { model.showQuickPanel() } label: { Text("Open", bundle: .module) }
            }
            SettingsToggleRow(symbol: "doc.on.clipboard", title: Text("Paste the entry straight away", bundle: .module),
                              caption: Text("Off, the entry only goes on the clipboard. Pasting needs the Accessibility permission.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.quickPanelPastes },
                                            set: { value in model.update { $0.quickPanelPastes = value } }))
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
        SettingsCard(Text("Shelf", bundle: .module)) {
            SettingsToggleRow(symbol: "tray.and.arrow.down", title: Text("Show a shelf next to the pointer while dragging", bundle: .module),
                              caption: Text("Drop files on it to park them on the way, and drag them out again later. It stays while it holds something.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.floatingShelf },
                                            set: { value in model.update { $0.floatingShelf = value } }))
        }
        SettingsCard(Text("Finder", bundle: .module)) {
            SettingsToggleRow(symbol: "scissors", title: Text("Cut and paste files with ⌘X and ⌘V", bundle: .module),
                              caption: Text("⌘X marks the selection, ⌘V moves it to the folder in front. Text fields keep their own cut and paste.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.finderCutAndPaste },
                                            set: { value in model.update { $0.finderCutAndPaste = value } }))
            SettingsToggleRow(symbol: "character.cursor.ibeam", title: Text("Rename with F2", bundle: .module),
                              caption: Text("Starts renaming the selected item, as Return does.", bundle: .module),
                              isOn: Binding(get: { model.settings.finderRenameWithF2 },
                                            set: { value in model.update { $0.finderRenameWithF2 = value } }))
            if model.finderKeysNeedAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.",
                                     bundle: .module))
            }
            Text("The buttons in the menu panel's clipboard tab ask once for permission to control Finder.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
