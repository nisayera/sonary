import AppKit
import SonaryCore
import SonaryUI
import SwiftUI

func dockActionTitle(_ action: DockClickAction) -> LocalizedStringKey {
    switch action {
    case .system: "Leave it to macOS"
    case .cycleWindows: "Cycle through its windows"
    case .minimizeAll: "Minimize all its windows"
    case .showAllWindows: "Show all its windows"
    case .hide: "Hide the app"
    }
}

func layoutTitle(_ action: LayoutAction) -> LocalizedStringKey {
    switch action {
    case .leftHalf: "Left half"
    case .rightHalf: "Right half"
    case .topHalf: "Top half"
    case .bottomHalf: "Bottom half"
    case .topLeft: "Top left quarter"
    case .topRight: "Top right quarter"
    case .bottomLeft: "Bottom left quarter"
    case .bottomRight: "Bottom right quarter"
    case .leftThird: "Left third"
    case .centerThird: "Center third"
    case .rightThird: "Right third"
    case .maximize: "Maximize"
    case .center: "Center"
    case .fillScreen: "Fill the screen"
    case .topLeftSixth: "Top left sixth"
    case .topCenterSixth: "Top center sixth"
    case .topRightSixth: "Top right sixth"
    case .bottomLeftSixth: "Bottom left sixth"
    case .bottomCenterSixth: "Bottom center sixth"
    case .bottomRightSixth: "Bottom right sixth"
    }
}

/// The shortcut a window command has right now, as the Shortcuts page set it, or a dash.
@MainActor
func currentShortcut(_ id: String) -> String {
    let combo = ShortcutStore.shared.combo(for: id)
    return combo.isEmpty ? "—" : shortcutDisplay(combo)
}

struct WindowsSettingsView: View {
    let model: WindowsModel

    var body: some View {
        SettingsCard(Text("Move with the keyboard held", bundle: .module)) {
            SettingsRow(symbol: "hand.draw", title: Text("Hold ⌃⌘ and drag", bundle: .module),
                        caption: Text("Moves the window under the pointer from anywhere in it, instead of hunting for the title bar. Dragging with the right button resizes.",
                                      bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.modifierDrag },
                                          set: { value in model.update { $0.modifierDrag = value } })) {
                    Text("Off", bundle: .module).tag(ModifierDragMode.off)
                    Text("Move", bundle: .module).tag(ModifierDragMode.move)
                    Text("Resize", bundle: .module).tag(ModifierDragMode.resize)
                    Text("Move and resize", bundle: .module).tag(ModifierDragMode.moveAndResize)
                } label: { EmptyView() }
                    .settingsControl()
            }
        }
        SettingsCard(Text("Dock", bundle: .module)) {
            SettingsRow(symbol: "dock.rectangle", title: Text("A click on the icon of the app in front", bundle: .module),
                        caption: Text("A click on an app in the background only brings it forward. Sonary adds this after the Dock has had the click, so the Dock keeps working.",
                                      bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.dockClickAction },
                                          set: { value in model.update { $0.dockClickAction = value } })) {
                    ForEach(DockClickAction.allCases) { Text(dockActionTitle($0), bundle: .module).tag($0) }
                } label: { EmptyView() }
                    .settingsControl()
            }
            SettingsToggleRow(symbol: "rectangle.on.rectangle",
                              title: Text("Window previews when the pointer rests on an icon", bundle: .module),
                              caption: Text("Shows that app's windows from every Space, which the Dock itself will not.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.dockPreviews },
                                            set: { value in model.update { $0.dockPreviews = value } }))
            if model.settings.dockPreviews || model.settings.switcherPreviews {
                Text("No window pictures while one of these apps is in front, such as games or video players.",
                     bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                AppListEditor(bundleIDs: Binding(get: { model.settings.previewPausingApps },
                                                 set: { value in model.update { $0.previewPausingApps = value } }),
                              addTitle: Text("Add app…", bundle: .module), removeLabel: Text("Remove app", bundle: .module))
            }
        }
        SettingsCard(Text("Green window button", bundle: .module)) {
            SettingsToggleRow(symbol: "arrow.up.left.and.arrow.down.right",
                              title: Text("The green button fills the screen", bundle: .module),
                              caption: Text("Instead of a full-screen Space. A second click puts the window back; ⌥-click keeps what macOS does.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.greenButtonMaximizes },
                                            set: { value in model.update { $0.greenButtonMaximizes = value } }))
            if model.settings.greenButtonMaximizes {
                Text("These apps still go full screen, such as games, emulators and video players.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                AppListEditor(bundleIDs: Binding(get: { model.settings.greenButtonExceptions },
                                                 set: { value in model.update { $0.greenButtonExceptions = value } }),
                              addTitle: Text("Add app…", bundle: .module), removeLabel: Text("Remove app", bundle: .module))
            }
        }
        SettingsCard(Text("Spaces", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.3.group",
                              title: Text("Keep the Spaces in the order I put them", bundle: .module),
                              caption: Text("macOS otherwise rearranges them by most recent use. Changing this restarts the Dock, which blinks once.",
                                            bundle: .module),
                              isOn: Binding(get: { model.spacesKeepTheirOrder },
                                            set: { model.setSpacesKeepTheirOrder($0) }))
        }
        SettingsCard(Text("Window layouts", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.split.2x1", title: Text("Keyboard shortcuts for window layouts", bundle: .module),
                              caption: Text("Moves and resizes the front window.", bundle: .module),
                              isOn: Binding(get: { model.settings.layoutShortcuts },
                                            set: { value in model.update { $0.layoutShortcuts = value } }))
            if model.settings.layoutShortcuts {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(LayoutAction.allCases, id: \.self) { action in
                        HStack {
                            Text(layoutTitle(action), bundle: .module)
                            Spacer()
                            Text(verbatim: currentShortcut("windows.layout.\(action.rawValue)"))
                                .font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Move to the next display", bundle: .module)
                        Spacer()
                        Text(verbatim: currentShortcut("windows.nextScreen")).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Put the window back", bundle: .module)
                        Spacer()
                        Text(verbatim: currentShortcut("windows.restore")).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text("Change any of them on the Shortcuts page; the sixths have none until you give them one.",
                     bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("These apps keep their own layout: shortcuts, screen edges and holding keys to drag leave them alone.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            AppListEditor(bundleIDs: Binding(get: { model.settings.layoutExcludedApps },
                                             set: { value in model.update { $0.layoutExcludedApps = value } }),
                          addTitle: Text("Add app…", bundle: .module), removeLabel: Text("Remove app", bundle: .module))
        }
        SettingsCard(Text("Window switcher", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.stack", title: Text("Window switcher on ⌃⌥Tab", bundle: .module),
                              caption: Text("Lists every open window with search, and brings the one you pick to the front.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.windowSwitcher },
                                            set: { value in model.update { $0.windowSwitcher = value } }))
            if model.settings.windowSwitcher {
                SettingsRow(symbol: "square.grid.2x2", title: Text("Look", bundle: .module),
                            caption: Text("The list finds a window by its title; the icons show one app each, like the macOS switcher.",
                                          bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.switcherStyle },
                                              set: { value in model.update { $0.switcherStyle = value } })) {
                        Text("Window list", bundle: .module).tag(SwitcherStyle.list)
                        Text("App icons", bundle: .module).tag(SwitcherStyle.icons)
                    } label: { EmptyView() }
                        .settingsControl()
                }
                SettingsToggleRow(symbol: "command", title: Text("Open it with ⌘Tab", bundle: .module),
                                  caption: Text("Takes ⌘Tab over from macOS: hold ⌘, press Tab to move on, ⇧Tab to go back, and let go to switch. The macOS switcher comes back when this is off or Sonary quits.",
                                                bundle: .module),
                                  isOn: Binding(get: { model.settings.switcherTakesCommandTab },
                                                set: { value in model.update { $0.switcherTakesCommandTab = value } }))
                if model.commandTabNeedsAccessibility {
                    SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.", bundle: .module))
                } else if model.commandTabKeepsSystemSwitcher {
                    SettingsWarning(Text("macOS kept its own switcher on, so ⌘Tab may open both.", bundle: .module))
                }
                SettingsToggleRow(symbol: "photo.on.rectangle", title: Text("Show a picture of each window", bundle: .module),
                                  caption: Text("Asks for the Screen Recording permission the first time.", bundle: .module),
                                  isOn: Binding(get: { model.settings.switcherPreviews },
                                                set: { value in model.update { $0.switcherPreviews = value } }))
                Button { model.showSwitcher() } label: { Text("Show it now", bundle: .module) }
                    .buttonStyle(.borderless)
            }
        }
        SettingsCard(Text("Dragging", bundle: .module)) {
            SettingsToggleRow(symbol: "rectangle.and.arrow.up.right.and.arrow.down.left",
                              title: Text("Snap windows at the screen edges", bundle: .module),
                              caption: Text("Drag a window against an edge or a corner and let go.", bundle: .module),
                              isOn: Binding(get: { model.settings.edgeSnapping },
                                            set: { value in model.update { $0.edgeSnapping = value } }))
            SettingsToggleRow(symbol: "cursorarrow.rays", title: Text("Focus follows the pointer", bundle: .module),
                              caption: Text("A window comes forward when the pointer rests on it.", bundle: .module),
                              isOn: Binding(get: { model.settings.focusFollowsMouse },
                                            set: { value in model.update { $0.focusFollowsMouse = value } }))
        }
        SettingsCard(Text("Closing", bundle: .module)) {
            SettingsToggleRow(symbol: "xmark.circle", title: Text("Quit an app when its last window closes", bundle: .module),
                              caption: Text("Finder and menu bar apps are never quit.", bundle: .module),
                              isOn: Binding(get: { model.settings.quitWhenLastWindowCloses },
                                            set: { value in model.update { $0.quitWhenLastWindowCloses = value } }))
        }
        SettingsCard(Text("Quit protection", bundle: .module)) {
            if model.quitProtectionNeedsAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.", bundle: .module))
            }
            SettingsToggleRow(symbol: "hand.raised", title: Text("Protect ⌘Q (quit)", bundle: .module),
                              caption: Text("Stops apps from closing by accident. Finder is never affected.", bundle: .module),
                              isOn: Binding(get: { model.settings.quitProtection },
                                            set: { value in model.update { $0.quitProtection = value } }))
            SettingsToggleRow(symbol: "xmark.square", title: Text("Protect ⌘W (close a window)", bundle: .module),
                              isOn: Binding(get: { model.settings.closeProtection },
                                            set: { value in model.update { $0.closeProtection = value } }))
            if model.settings.quitProtection || model.settings.closeProtection {
                SettingsRow(symbol: "hand.raised", title: Text("Confirm by", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.quitConfirmation },
                                              set: { value in model.update { $0.quitConfirmation = value } })) {
                        Text("Pressing twice", bundle: .module).tag(QuitConfirmation.pressTwice)
                        Text("Holding the keys", bundle: .module).tag(QuitConfirmation.hold)
                        Text("Adding ⌥ (⌥⌘Q)", bundle: .module).tag(QuitConfirmation.extraModifier)
                    } label: { EmptyView() }
                        .settingsControl()
                }
                Group {
                    if model.settings.protectedApps.isEmpty {
                        Text("Every app is protected. Add apps to protect only those.", bundle: .module)
                    } else {
                        Text("Only these apps are protected.", bundle: .module)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(model.settings.protectedApps, id: \.self) { bundleID in
                    SettingsRow(symbol: "app.dashed", title: Text(verbatim: bundleID)) {
                        Button(role: .destructive) {
                            model.update { $0.protectedApps.removeAll { $0 == bundleID } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove app", bundle: .module))
                    }
                }
                Button { addProtectedApp() } label: {
                    Label { Text("Add app…", bundle: .module) } icon: { Image(systemName: "plus") }
                }
            }
        }
    }
}

extension WindowsSettingsView {
    fileprivate func addProtectedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.update { if !$0.protectedApps.contains(id) { $0.protectedApps.append(id) } }
    }
}

/// The hint shown while a protected shortcut waits. While it is being held, a bar
/// fills up so there is something to look at and a reason to keep holding.
struct QuitHintView: View {
    let text: String
    /// Nil for the press-twice hint, which has no bar.
    let progress: (() -> Double)?
    @State private var filled: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: text).font(.title3.weight(.semibold))
            if progress != nil {
                ProgressView(value: filled)
                    .progressViewStyle(.linear)
                    .tint(Color.sonaryAccent)
                    .frame(width: 180)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task {
            guard let progress else { return }
            while !Task.isCancelled {
                filled = progress()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}
