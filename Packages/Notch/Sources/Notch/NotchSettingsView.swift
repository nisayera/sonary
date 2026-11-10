import SonaryUI
import SwiftUI

struct NotchSettingsView: View {
    let model: NotchModel

    var body: some View {
        SettingsCard(Text("Widgets", bundle: .module)) {
            ForEach(NotchWidget.allCases, id: \.self) { widget in
                SettingsToggleRow(
                    symbol: widget.symbol,
                    title: Text(widgetTitle(widget), bundle: .module),
                    caption: caption(for: widget),
                    isOn: Binding(get: { model.settings.isOn(widget) }, set: { model.setWidget(widget, on: $0) })
                )
            }
        }
        if model.settings.widgets.count > 1 {
            SettingsCard(Text("Order in the island", bundle: .module)) {
                ForEach(Array(model.settings.widgets.enumerated()), id: \.element) { index, widget in
                    SettingsRow(symbol: widget.symbol, title: Text(widgetTitle(widget), bundle: .module)) {
                        Button { model.moveWidget(widget, forward: true) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel(Text("Move up", bundle: .module))
                        Button { model.moveWidget(widget, forward: false) } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == model.settings.widgets.count - 1)
                            .accessibilityLabel(Text("Move down", bundle: .module))
                    }
                }
            }
        }
        SettingsCard(Text("Opening", bundle: .module)) {
            SettingsToggleRow(symbol: "cursorarrow.rays", title: Text("Open when the pointer rests on it", bundle: .module),
                              caption: Text("Off, the island only opens with a click or a scroll.", bundle: .module),
                              isOn: Binding(get: { model.settings.openOnHover },
                                            set: { value in model.updateSettings { $0.openOnHover = value } }))
            if model.settings.openOnHover {
                SettingsRow(symbol: "hourglass", title: Text("Wait before opening", bundle: .module)) {
                    Picker(selection: Binding(get: { model.settings.hoverDelay },
                                              set: { value in model.updateSettings { $0.hoverDelay = value } })) {
                        Text("At once", bundle: .module).tag(0.0)
                        Text(verbatim: "0.2 s").tag(0.2)
                        Text(verbatim: "0.5 s").tag(0.5)
                        Text(verbatim: "1 s").tag(1.0)
                    } label: { EmptyView() }
                        .settingsControl()
                }
            }
        }
        SettingsCard(Text("Timer", bundle: .module)) {
            SettingsRow(symbol: "timer", title: Text("Countdowns offered", bundle: .module),
                        caption: Text("Minutes, separated by commas. Up to five.", bundle: .module)) {
                TextField(text: Binding(
                    get: { model.settings.timerPresets.map(String.init).joined(separator: ", ") },
                    set: { text in
                        let minutes = parseTimerPresets(text)
                        if !minutes.isEmpty { model.updateSettings { $0.timerPresets = minutes } }
                    }
                )) { EmptyView() }
                    .settingsControl()
            }
        }
        SettingsCard(Text("Batteries", bundle: .module)) {
            SettingsToggleRow(
                symbol: "battery.25percent",
                title: Text("Warn when an accessory battery is low", bundle: .module),
                caption: Text("A notice once a mouse, keyboard or headphones fall to 20 percent. Needs the batteries widget.", bundle: .module),
                isOn: Binding(get: { model.settings.lowBatteryWarning }, set: { model.setLowBatteryWarning($0) })
            )
        }
        SettingsCard(Text("Display", bundle: .module)) {
            SettingsToggleRow(
                symbol: "display",
                title: Text("Show on displays without a notch", bundle: .module),
                caption: Text("Draws a small island at the top centre of the main display.", bundle: .module),
                isOn: Binding(get: { model.settings.showOnScreensWithoutNotch },
                              set: { model.setShowOnScreensWithoutNotch($0) })
            )
        }
        SettingsCard(Text("Usage", bundle: .module)) {
            Text("Move the pointer onto the island to open it. Click it to keep it open, click anywhere else to close it.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func caption(for widget: NotchWidget) -> Text? {
        switch widget {
        case .music: Text("Music and Spotify, with play, pause and skip.", bundle: .module)
        case .calendar: Text("Today's remaining events. Asks for calendar access.", bundle: .module)
        case .timer: Text("Quick countdowns with a sound at the end.", bundle: .module)
        case .downloads: Text("Your newest downloads; click to open or drag them out.", bundle: .module)
        case .batteries: Text("Mouse, keyboard, trackpad and headphones.", bundle: .module)
        case .shelf: Text("Park files on the notch and drag them out again.", bundle: .module)
        case .camera: Text("A live picture from the front camera, for checking yourself before a call.", bundle: .module)
        case .controls: Text("Volume and brightness sliders, while Sound and Display are on.", bundle: .module)
        case .notes: Text("The scratchpad's current note, while Tools is on.", bundle: .module)
        }
    }
}
