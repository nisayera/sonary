import Foundation
import Observation
import SonaryCore
import SonaryUI
import SwiftUI

/// What the shortcut sheet remembers.
public struct ShortcutSheetSettings: Codable, Equatable, Sendable {
    /// How ⌘ opens the sheet; `none` leaves it to its own shortcut.
    public var trigger: SheetTrigger = .hold
    /// How long ⌘ has to be held, in seconds.
    public var delay = 1.0
    /// The sheet's columns; 0 lets the screen's width decide.
    public var columns = 0
    public var appearance: SheetAppearance = .system
    /// The sheet ends with the shortcuts macOS answers in every app.
    public var system = true
    /// Shortcuts no menu shows, written down by hand.
    public var custom: [CustomSheetShortcut] = []
    /// Favourites and hidden shortcuts, by the app's bundle identifier.
    public var marks: [String: SheetMarks] = [:]
    public init() {}
}

/// The shortcut sheet as a module of its own: it shows every keyboard shortcut of the app in
/// front, on a held ⌘ or on a shortcut, and keeps what the user marked.
@MainActor
@Observable
public final class ShortcutSheetModel {
    public private(set) var settings: ShortcutSheetSettings
    /// Set when the sheet could not start watching, which means Accessibility is missing.
    public private(set) var needsAccessibility = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let controller = ShortcutSheetController()
    @ObservationIgnored private var running = false
    static let toggleID = "shortcutsheet.toggle"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = StoredSettings.load(ShortcutSheetSettings.self, key: "shortcutsheet.settings", from: defaults,
                                       fallback: ShortcutSheetSettings())
    }

    func start() {
        running = true
        applyShortcut()
        applyWatching()
    }

    func stop() {
        running = false
        applyShortcut()
        applyWatching()
    }

    public func update(_ change: (inout ShortcutSheetSettings) -> Void) {
        let before = settings.trigger
        change(&settings)
        StoredSettings.save(settings, key: "shortcutsheet.settings", to: defaults)
        configure()
        if before != settings.trigger { applyWatching() }
    }

    /// Opens the sheet, or closes it when it is open.
    public func toggle() {
        configure()
        controller.toggle()
    }

    private func configure() {
        controller.delay = settings.delay
        controller.trigger = settings.trigger
        controller.columns = settings.columns
        controller.appearance = settings.appearance
        controller.showsSystem = settings.system
        controller.custom = settings.custom
        controller.marks = { [weak self] bundleID in self?.settings.marks[bundleID] ?? SheetMarks() }
        controller.setMarks = { [weak self] bundleID, marks in
            self?.update { $0.marks[bundleID] = marks.isEmpty ? nil : marks }
        }
    }

    private func applyWatching() {
        configure()
        guard running, settings.trigger != .shortcutOnly else {
            controller.stopWatching()
            needsAccessibility = false
            return
        }
        needsAccessibility = !controller.startWatching()
    }

    private func applyShortcut() {
        let shortcuts = ShortcutStore.shared
        shortcuts.describe([
            ShortcutDefinition(id: Self.toggleID, title: String(localized: "Shortcut sheet", bundle: .module),
                               group: String(localized: "Shortcut sheet", bundle: .module), defaultCombo: .none),
        ])
        shortcuts.unbind(Self.toggleID)
        guard running else { return }
        shortcuts.bind(Self.toggleID) { [weak self] in self?.toggle() }
    }
}

@MainActor
@Observable
public final class ShortcutSheetModule: SonaryModule {
    public let id = "shortcutsheet"
    public let title = LocalizedStringResource("Shortcut sheet", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "command"
    /// The menus are read through Accessibility; the sheet asks for it when it starts.
    public var requiredPermissions: [SonaryPermission] { [] }
    public let model: ShortcutSheetModel

    public init(defaults: UserDefaults = .standard) {
        model = ShortcutSheetModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }
    public func makeSettingsView() -> AnyView { AnyView(ShortcutSheetSettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }
}

struct ShortcutSheetSettingsView: View {
    let model: ShortcutSheetModel

    var body: some View {
        SettingsCard(Text("Opening", bundle: .module)) {
            SettingsRow(symbol: "hand.tap", title: Text("Opens with", bundle: .module),
                        caption: Text("Hold ⌘ alone, or press it twice and keep the second press down. Let go to close the sheet, or click a shortcut to run it. Needs Accessibility.",
                                      bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.trigger },
                                          set: { value in
                                              model.update {
                                                  $0.trigger = value
                                                  if value == .hold, $0.delay < 0.5 { $0.delay = 0.5 }
                                              }
                                          })) {
                    Text("Holding ⌘", bundle: .module).tag(SheetTrigger.hold)
                    Text("Pressing ⌘ twice and holding", bundle: .module).tag(SheetTrigger.doubleHold)
                    Text("Only its own shortcut", bundle: .module).tag(SheetTrigger.shortcutOnly)
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 230)
            }
            if model.settings.trigger != .shortcutOnly {
                SettingsRow(symbol: "hourglass", title: Text("Hold ⌘ for", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.delay },
                                              set: { value in model.update { $0.delay = value } })) {
                        if model.settings.trigger == .doubleHold {
                            Text("No wait", bundle: .module).tag(0.0)
                        }
                        Text(verbatim: "0.5 s").tag(0.5)
                        Text(verbatim: "1 s").tag(1.0)
                        Text(verbatim: "1.5 s").tag(1.5)
                        Text(verbatim: "2 s").tag(2.0)
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 100)
                }
            }
            if model.needsAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then turn the module off and on again.",
                                     bundle: .module))
            }
            Text("It can also open on a shortcut of its own, from the Shortcuts page; then it stays open, with a search, until you close it.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(Text("Look", bundle: .module)) {
            SettingsRow(symbol: "rectangle.split.3x1", title: Text("Columns", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.columns },
                                          set: { value in model.update { $0.columns = value } })) {
                    Text("Automatic", bundle: .module).tag(0)
                    ForEach(2...5, id: \.self) { count in Text(verbatim: "\(count)").tag(count) }
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 130)
            }
            SettingsRow(symbol: "circle.lefthalf.filled", title: Text("Appearance", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.appearance },
                                          set: { value in model.update { $0.appearance = value } })) {
                    Text("Like the system", bundle: .module).tag(SheetAppearance.system)
                    Text("Light", bundle: .module).tag(SheetAppearance.light)
                    Text("Dark", bundle: .module).tag(SheetAppearance.dark)
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 150)
            }
            SettingsToggleRow(symbol: "apple.logo", title: Text("Show the system's shortcuts too", bundle: .module),
                              caption: Text("The sheet ends with the shortcuts macOS answers in every app, such as Spotlight and screenshots.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.system },
                                            set: { value in model.update { $0.system = value } }))
        }
        SettingsCard(Text("Your shortcuts", bundle: .module)) {
            SheetCustomShortcutsEditor(model: model)
            if model.settings.marks.values.contains(where: { !$0.isEmpty }) {
                SettingsRow(symbol: "star.slash", title: Text("Favourites and hidden shortcuts", bundle: .module)) {
                    Button { model.update { $0.marks = [:] } } label: { Text("Reset", bundle: .module) }
                }
            }
        }
    }
}

/// The shortcuts written down by hand, under "My shortcuts" in the sheet: a name, the
/// keys as they should be printed, and the app they belong to.
struct SheetCustomShortcutsEditor: View {
    let model: ShortcutSheetModel

    private var apps: [(id: String, name: String)] {
        var seen = Set<String>()
        var result: [(id: String, name: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { continue }
            result.append((id, app.localizedName ?? id))
        }
        for entry in model.settings.custom {
            if let id = entry.bundleID, seen.insert(id).inserted { result.append((id, id)) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("My shortcuts", bundle: .module).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    model.update { $0.custom.append(CustomSheetShortcut(title: "", keys: "")) }
                } label: {
                    Label { Text("Add", bundle: .module) } icon: { Image(systemName: "plus") }
                }
            }
            Text("For shortcuts the menus do not show. Write the keys the way they should be printed, for example ⌃⌥T. They are only listed; a click does not run them.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            let apps = apps
            ForEach(model.settings.custom) { entry in
                HStack(spacing: 6) {
                    TextField(text: binding(entry.id, \.title)) { Text("Name", bundle: .module) }
                        .textFieldStyle(.roundedBorder)
                    TextField(text: binding(entry.id, \.keys)) { Text("Keys", bundle: .module) }
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    Picker(selection: Binding(get: { entry.bundleID ?? "" },
                                              set: { value in
                                                  model.update { settings in
                                                      guard let index = settings.custom.firstIndex(where: { $0.id == entry.id }) else { return }
                                                      settings.custom[index].bundleID = value.isEmpty ? nil : value
                                                  }
                                              })) {
                        Text("All apps", bundle: .module).tag("")
                        ForEach(apps, id: \.id) { app in Text(verbatim: app.name).tag(app.id) }
                    } label: { EmptyView() }
                        .labelsHidden().frame(width: 140)
                    Button {
                        model.update { $0.custom.removeAll { $0.id == entry.id } }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Remove", bundle: .module))
                }
            }
        }
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<CustomSheetShortcut, String>) -> Binding<String> {
        Binding(get: { model.settings.custom.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { value in
                    model.update { settings in
                        guard let index = settings.custom.firstIndex(where: { $0.id == id }) else { return }
                        settings.custom[index][keyPath: keyPath] = value
                    }
                })
    }
}
