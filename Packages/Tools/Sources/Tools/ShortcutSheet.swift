import AppKit
import ApplicationServices
import SonaryCore
import SonaryUI
import SwiftUI

// MARK: Logic

/// One menu command that has a keyboard shortcut.
public struct SheetShortcut: Equatable, Sendable, Identifiable {
    public var title: String
    /// The keys as they are printed, such as "⇧⌘S".
    public var keys: String
    /// The menu item behind it, as `sheetKey` names it; nil for a shortcut no menu holds.
    public var origin: String?
    public var id: String { title + "\u{1}" + keys }

    public init(title: String, keys: String) {
        self.title = title
        self.keys = keys
    }
}

/// The shortcuts of one menu, such as "File".
public struct SheetGroup: Equatable, Sendable, Identifiable {
    public var title: String
    public var shortcuts: [SheetShortcut]
    public var id: String { title }

    public init(title: String, shortcuts: [SheetShortcut]) {
        self.title = title
        self.shortcuts = shortcuts
    }
}

/// The keys of a menu item as the menu prints them. The accessibility API gives the
/// modifiers as bits (1 shift, 2 option, 4 control, 8 "no command"), and the key as a
/// character, a glyph number for keys without one, or a virtual key code. Nil when the
/// item has no shortcut.
public func menuShortcutLabel(character: String?, glyph: Int?, virtualKey: Int?, modifiers: Int) -> String? {
    let key: String
    if let glyph, let name = menuGlyphNames[glyph] {
        key = name
    } else if let character, !character.isEmpty, character != "\0" {
        key = character == " " ? "Space" : character.uppercased()
    } else if let virtualKey, virtualKey > 0, virtualKey < 128 {
        key = keyName(virtualKey)
    } else {
        return nil
    }
    var text = ""
    if modifiers & 4 != 0 { text += "⌃" }
    if modifiers & 2 != 0 { text += "⌥" }
    if modifiers & 1 != 0 { text += "⇧" }
    if modifiers & 8 == 0 { text += "⌘" }
    return text + key
}

/// The glyph numbers menus use for keys that have no character.
let menuGlyphNames: [Int: String] = [
    2: "⇥", 3: "⇤", 4: "⌤", 9: "Space", 10: "⌦", 11: "↩", 23: "⌫", 27: "⎋", 28: "⌧",
    98: "⇞", 99: "⇪", 100: "←", 101: "→", 104: "↑", 106: "↓", 107: "⇟",
    111: "F1", 112: "F2", 113: "F3", 114: "F4", 115: "F5", 116: "F6",
    117: "F7", 118: "F8", 119: "F9", 120: "F10", 121: "F11", 122: "F12",
]

/// Spreads the menus over columns of about the same height, keeping their order, so the
/// sheet reads left to right like the menu bar.
public func sheetColumns(_ groups: [SheetGroup], count: Int) -> [[SheetGroup]] {
    let count = max(1, count)
    // A heading takes about as much room as two shortcuts.
    func height(_ group: SheetGroup) -> Int { group.shortcuts.count + 2 }
    let total = groups.reduce(0) { $0 + height($1) }
    let target = max(1, Int((Double(total) / Double(count)).rounded(.up)))
    var columns: [[SheetGroup]] = [[]]
    var filled = 0
    for group in groups {
        if filled > 0, filled + height(group) / 2 > target, columns.count < count {
            columns.append([])
            filled = 0
        }
        columns[columns.count - 1].append(group)
        filled += height(group)
    }
    return columns
}

/// Narrows the sheet to the shortcuts whose name contains what was typed.
public func filteredSheet(_ groups: [SheetGroup], query: String) -> [SheetGroup] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return groups }
    return groups.compactMap { group in
        let hits = group.shortcuts.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return hits.isEmpty ? nil : SheetGroup(title: group.title, shortcuts: hits)
    }
}

/// Decides when holding ⌘ alone has lasted long enough. Any other key or modifier in
/// between means a shortcut is being typed, and the hold does not count.
public struct CommandHold: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var isHolding = false

    public init() {}

    /// The modifiers changed. Returns the generation to wait on when ⌘ alone just went
    /// down, nil otherwise.
    public mutating func flagsChanged(command: Bool, others: Bool) -> Int? {
        let alone = command && !others
        if alone, !isHolding {
            isHolding = true
            generation += 1
            return generation
        }
        if !alone {
            isHolding = false
            generation += 1
        }
        return nil
    }

    /// A key or a mouse button went down: this is not a bare hold any more.
    public mutating func interrupted() {
        generation += 1
    }

    /// Whether the wait started for `generation` still stands.
    public func shouldFire(_ generation: Int) -> Bool {
        isHolding && generation == self.generation
    }
}

// MARK: Reading the menus

extension MenuBarReader {
    /// Every menu command of the app that has a keyboard shortcut, menu by menu, with the
    /// element to press for each.
    static func shortcutSheet(for app: NSRunningApplication) -> (groups: [SheetGroup], elements: [String: AXUIElement]) {
        guard AXIsProcessTrusted() else { return ([], [:]) }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return ([], [:]) }
        var groups: [SheetGroup] = []
        var elements: [String: AXUIElement] = [:]
        for menu in sheetChildren(of: unsafeDowncast(bar, to: AXUIElement.self)) {
            guard let title = sheetString(menu, kAXTitleAttribute), title != "Apple" else { continue }
            var found: [SheetShortcut] = []
            collectShortcuts(from: menu, prefix: "", into: &found, elements: &elements, group: title, depth: 0)
            if !found.isEmpty { groups.append(SheetGroup(title: title, shortcuts: found)) }
        }
        return (groups, elements)
    }

    private static func collectShortcuts(from element: AXUIElement, prefix: String, into found: inout [SheetShortcut],
                                         elements: inout [String: AXUIElement], group: String, depth: Int) {
        guard depth < 5, found.count < 120 else { return }
        for child in sheetChildren(of: element) {
            guard let title = sheetString(child, kAXTitleAttribute), !title.isEmpty else {
                collectShortcuts(from: child, prefix: prefix, into: &found, elements: &elements, group: group, depth: depth + 1)
                continue
            }
            let name = prefix.isEmpty ? title : prefix + " ▸ " + title
            let keys = menuShortcutLabel(character: sheetString(child, kAXMenuItemCmdCharAttribute),
                                         glyph: sheetNumber(child, kAXMenuItemCmdGlyphAttribute),
                                         virtualKey: sheetNumber(child, kAXMenuItemCmdVirtualKeyAttribute),
                                         modifiers: sheetNumber(child, kAXMenuItemCmdModifiersAttribute) ?? 0)
            if let keys {
                let shortcut = SheetShortcut(title: name, keys: keys)
                if elements[group + "\u{1}" + shortcut.id] == nil {
                    found.append(shortcut)
                    elements[group + "\u{1}" + shortcut.id] = child
                }
            } else {
                collectShortcuts(from: child, prefix: name, into: &found, elements: &elements, group: group, depth: depth + 1)
            }
        }
    }

    private static func sheetChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func sheetString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func sheetNumber(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }
}

// MARK: Panel

final class ShortcutSheetPanel: NSPanel {
    /// A sheet that stays takes the keyboard for its search; one shown by a held ⌘ does not.
    var takesKeys = false
    override var canBecomeKey: Bool { takesKeys }
}

/// Shows every keyboard shortcut of the app in front, the way CheatSheet and KeyClu do:
/// hold ⌘ for a moment, or press it twice and hold, and the sheet appears; let go and it
/// is gone. A click on a shortcut runs it.
@MainActor
final class ShortcutSheetController {
    private var panel: ShortcutSheetPanel?
    private var monitors: [Any] = []
    private var hold = CommandHold()
    private var doubleHold = CommandDoubleHold()
    private var waitTask: Task<Void, Never>?
    /// Shown by holding ⌘, so letting go closes it; a sheet opened by its shortcut stays.
    private var shownByHold = false
    var delay: Double = 1.0
    var trigger: SheetTrigger = .hold
    var columns = 0
    var appearance: SheetAppearance = .system
    var showsSystem = true
    var custom: [CustomSheetShortcut] = []
    /// The marks of the app with this bundle identifier, and the way to keep new ones.
    var marks: (String) -> SheetMarks = { _ in SheetMarks() }
    var setMarks: (String, SheetMarks) -> Void = { _, _ in }

    var isVisible: Bool { panel?.isVisible == true }

    /// Starts watching for a held ⌘. False without Accessibility, which the menus need too.
    @discardableResult
    func startWatching() -> Bool {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return false }
        guard monitors.isEmpty else { return true }
        let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = modifiers.contains(.command)
            let others = !modifiers.intersection([.shift, .option, .control, .function]).isEmpty
            let time = event.timestamp
            MainActor.assumeIsolated { self?.flagsChanged(command: command, others: others, at: time) }
        }
        let other = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hold.interrupted()
                self?.doubleHold.interrupted()
            }
        }
        monitors = [flags, other].compactMap { $0 }
        return true
    }

    func stopWatching() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        waitTask?.cancel()
        hold = CommandHold()
        doubleHold = CommandDoubleHold()
        close()
    }

    private func flagsChanged(command: Bool, others: Bool, at time: Double) {
        let single = hold.flagsChanged(command: command, others: others)
        let double = doubleHold.flagsChanged(command: command, others: others, at: time)
        let trigger = trigger
        guard trigger != .shortcutOnly else { return }
        guard let generation = trigger == .hold ? single : double else {
            let holding = trigger == .hold ? hold.isHolding : doubleHold.isHolding
            if !holding, shownByHold { close() }
            return
        }
        waitTask?.cancel()
        // A plain hold needs its wait, or every ⌘ shortcut would flash the sheet.
        let delay = trigger == .hold ? max(0.3, delay) : delay
        waitTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            let stands = trigger == .hold ? self.hold.shouldFire(generation) : self.doubleHold.shouldFire(generation)
            if stands { self.show(byHold: true) }
        }
    }

    /// Opens the sheet, or closes it when it is open: for the keyboard shortcut and the panel.
    func toggle() {
        if isVisible { close() } else { show(byHold: false) }
    }

    func close() {
        panel?.orderOut(nil)
        shownByHold = false
    }

    private func show(byHold: Bool) {
        guard let app = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let sheet = MenuBarReader.shortcutSheet(for: app)
        let bundleID = app.bundleIdentifier ?? ""
        let mine = customShortcuts(custom, for: app.bundleIdentifier)
        let system = showsSystem ? systemSheetShortcuts() : []
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let columns = sheetColumnCount(chosen: columns, screenWidth: visible.width,
                                       hasShortcuts: !(sheet.groups.isEmpty && mine.isEmpty && system.isEmpty))
        let size = CGSize(width: min(visible.width - 80, CGFloat(columns) * 300 + 48),
                          height: min(visible.height - 80, 640))
        let panel = panel ?? ShortcutSheetPanel(contentRect: CGRect(origin: .zero, size: size),
                                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                                defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.takesKeys = !byHold
        switch appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.contentView = NSHostingView(rootView: ShortcutSheetView(
            appName: app.localizedName ?? "", icon: app.icon, groups: sheet.groups, custom: mine, system: system,
            columns: columns, stays: !byHold, marks: marks(bundleID),
            keep: { [weak self] marks in
                guard !bundleID.isEmpty else { return }
                self?.setMarks(bundleID, marks)
            },
            run: { [weak self] shortcut in
                guard let origin = shortcut.origin, let element = sheet.elements[origin] else { return }
                self?.close()
                MenuBarReader.press(element)
            },
            close: { [weak self] in self?.close() }
        ).frame(width: size.width, height: size.height))
        panel.setContentSize(size)
        panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        self.panel = panel
        shownByHold = byHold
        if byHold { panel.orderFrontRegardless() } else { panel.makeKeyAndOrderFront(nil) }
    }
}

struct ShortcutSheetView: View {
    let appName: String
    let icon: NSImage?
    let groups: [SheetGroup]
    let custom: [SheetShortcut]
    let system: [SheetShortcut]
    let columns: Int
    /// Opened by its shortcut: it stays, so it gets a search field and a close button.
    let stays: Bool
    @State var marks: SheetMarks
    let keep: (SheetMarks) -> Void
    let run: (SheetShortcut) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var showHidden = false
    @FocusState private var searching: Bool

    private var favouritesTitle: String { String(localized: "Favourites", bundle: .module) }

    private var shown: [SheetGroup] {
        let titles = SheetGroupTitles(favourites: favouritesTitle,
                                      mine: String(localized: "My shortcuts", bundle: .module),
                                      system: String(localized: "System", bundle: .module))
        return filteredSheet(arrangedSheet(groups, marks: marks, custom: custom, system: system,
                                           showHidden: showHidden, titles: titles), query: query)
    }

    var body: some View {
        let shown = shown
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: appName).font(.system(size: 15, weight: .bold))
                    Text("\(shown.reduce(0) { $0 + $1.shortcuts.count }) keyboard shortcuts", bundle: .module)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if stays {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(text: $query) { Text("Search", bundle: .module) }
                            .textFieldStyle(.plain)
                            .focused($searching)
                            .frame(width: 150)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    if !marks.hidden.isEmpty {
                        Button { showHidden.toggle() } label: {
                            Image(systemName: showHidden ? "eye" : "eye.slash").font(.system(size: 13))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(Text("Show hidden shortcuts", bundle: .module))
                        .accessibilityLabel(Text("Show hidden shortcuts", bundle: .module))
                    }
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Close", bundle: .module))
                } else {
                    Text("Let go of ⌘ to close. Click a shortcut to run it.", bundle: .module)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard").font(.system(size: 30, weight: .light)).foregroundStyle(Color.sonaryAccent)
                    if query.isEmpty {
                        Text("This app shows no shortcuts in its menus.", bundle: .module).foregroundStyle(.secondary)
                    } else {
                        Text("No shortcut matches the search.", bundle: .module).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(sheetColumns(shown, count: columns).enumerated()), id: \.offset) { _, column in
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(column) { group in groupView(group) }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
            if stays {
                Text("Secondary-click a shortcut to keep it under Favourites or to hide it.", bundle: .module)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onExitCommand(perform: close)
        .onAppear { if stays { searching = true } }
    }

    private func change(_ edit: (inout SheetMarks) -> Void) {
        edit(&marks)
        keep(marks)
    }

    private func groupView(_ group: SheetGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: group.title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.sonaryAccent)
                .padding(.bottom, 2)
            ForEach(group.shortcuts) { shortcut in
                let starred = shortcut.origin.map { marks.starred.contains($0) } ?? false
                let hidden = shortcut.origin.map { marks.hidden.contains($0) } ?? false
                Button { run(shortcut) } label: {
                    HStack(spacing: 8) {
                        if starred, group.title != favouritesTitle {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                        }
                        Text(verbatim: shortcut.title).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(verbatim: shortcut.keys)
                            .font(.system(size: 11.5, weight: .semibold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .font(.system(size: 12))
                    .opacity(hidden ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let origin = shortcut.origin {
                        Button {
                            change { $0.toggleStar(origin) }
                        } label: {
                            if starred {
                                Label { Text("Remove from Favourites", bundle: .module) } icon: { Image(systemName: "star.slash") }
                            } else {
                                Label { Text("Add to Favourites", bundle: .module) } icon: { Image(systemName: "star") }
                            }
                        }
                        Button {
                            change { $0.toggleHidden(origin) }
                        } label: {
                            if hidden {
                                Label { Text("Show again", bundle: .module) } icon: { Image(systemName: "eye") }
                            } else {
                                Label { Text("Hide: I know this one", bundle: .module) } icon: { Image(systemName: "eye.slash") }
                            }
                        }
                    }
                }
            }
        }
    }
}
