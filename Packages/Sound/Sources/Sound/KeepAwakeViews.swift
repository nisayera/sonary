import AppKit
import SonaryUI
import SwiftUI

func keepAwakeTitle(_ duration: KeepAwakeDuration) -> LocalizedStringKey {
    switch duration {
    case .fifteenMinutes: "15 min"
    case .oneHour: "1 h"
    case .twoHours: "2 h"
    case .indefinitely: "Until I turn it off"
    }
}

private func keepAwakeSymbol(_ duration: KeepAwakeDuration) -> String {
    switch duration {
    case .fifteenMinutes: "timer"
    case .oneHour: "clock"
    case .twoHours: "clock.badge"
    case .indefinitely: "infinity"
    }
}

/// The keep awake tab of the menu panel: what runs now, then every way to start it as one row
/// each, so no button label is cut short.
struct KeepAwakePopoverView: View {
    let model: SoundModel
    /// The time picked for "awake until", an hour from when the panel opened.
    @State private var awakeUntil = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.spacing) {
            if model.keepAwakeActive {
                running
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    PanelSectionTitle(Text("Duration", bundle: .module))
                        .padding(.horizontal, 2)
                    PanelGroup {
                        ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                            startRow(keepAwakeSymbol(duration), Text(keepAwakeTitle(duration), bundle: .module)) {
                                model.setKeepAwake(duration, on: true)
                            }
                        }
                        HStack(spacing: PanelMetrics.rowIconSpacing) {
                            IconBadge(symbol: "alarm", size: PanelMetrics.rowIconWidth)
                            Text("Until", bundle: .module)
                                .font(.system(size: 12, weight: .semibold))
                            DatePicker(selection: $awakeUntil, displayedComponents: .hourAndMinute) { EmptyView() }
                                .labelsHidden()
                                .controlSize(.small)
                            Spacer(minLength: 4)
                            Button { model.keepAwake(until: awakeUntil) } label: {
                                Text("Start", bundle: .module)
                            }
                            .controlSize(.small)
                        }
                        .panelRowInsets()
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    PanelSectionTitle(Text("As long as", bundle: .module))
                        .padding(.horizontal, 2)
                    PanelGroup {
                        if !model.settings.keepAwakeApp.isEmpty {
                            startRow("app.badge.checkmark",
                                     Text("While \(model.appName(for: model.settings.keepAwakeApp)) runs", bundle: .module)) {
                                model.keepAwakeWhileAppRuns(model.settings.keepAwakeApp)
                            }
                        }
                        startRow("powerplug", Text("While plugged in", bundle: .module)) {
                            model.keepAwakeWhilePowered()
                        }
                        if model.hasExternalDisplay {
                            startRow("display", Text("While a display is attached", bundle: .module)) {
                                model.keepAwakeWhileDisplayConnected()
                            }
                        }
                    }
                }
            }
        }
    }

    /// What keeps the Mac awake now, and the button that ends it.
    private var running: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "cup.and.saucer.fill", size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awake", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
                Group {
                    if let ends = model.keepAwakeEndsAt {
                        Text("Awake until \(ends.formatted(date: .omitted, time: .shortened))", bundle: .module)
                    } else {
                        Text("Awake until you turn it off", bundle: .module)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { model.setKeepAwake(nil, on: false) } label: { Text("Stop", bundle: .module) }
                .controlSize(.small)
        }
        .padding(PanelMetrics.cardPadding)
        .panelCard(padded: false)
    }

    /// One way to start keep awake, as a whole row that can be clicked.
    private func startRow(_ symbol: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PanelRow(symbol: symbol, title: title) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }
}

struct KeepAwakeSettingsView: View {
    let model: SoundModel

    var body: some View {
        SettingsCard(Text("Keep awake", bundle: .module)) {
            SettingsToggleRow(symbol: "laptopcomputer", title: Text("Stay awake with the lid closed", bundle: .module),
                              caption: Text("Holds the stronger assertion, so an external display keeps working.", bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeWithClosedLid },
                                            set: { value in model.update { $0.keepAwakeWithClosedLid = value } }))
            SettingsToggleRow(symbol: "cup.and.saucer", title: Text("Show a cup in the menu bar while awake", bundle: .module),
                              caption: Text("Its menu says until when, and stops keep awake.", bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeMenuBarIcon },
                                            set: { value in model.update { $0.keepAwakeMenuBarIcon = value } }))
            SettingsToggleRow(symbol: "cursorarrow.motionlines", title: Text("Nudge the pointer now and then", bundle: .module),
                              caption: Text("Moves it by one pixel and back every minute or so, for apps that mark you away when there is no input. Needs Accessibility.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeNudgesPointer },
                                            set: { value in model.update { $0.keepAwakeNudgesPointer = value } }))
            HStack {
                Text("Keep awake while this app runs", bundle: .module)
                Spacer()
                Picker(selection: Binding(get: { model.settings.keepAwakeApp },
                                          set: { value in model.update { $0.keepAwakeApp = value } })) {
                    Text("None", bundle: .module).tag("")
                    ForEach(model.runningApps) { Text($0.name).tag($0.id) }
                } label: { EmptyView() }
                    .labelsHidden()
                    .frame(maxWidth: 180)
            }
        }
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Start keep awake for a while, until a time, or as long as an app runs, the Mac is plugged in or a display is attached, from the menu panel's keep awake tab.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
