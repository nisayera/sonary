import SonaryUI
import SwiftUI

struct DisplayPopoverView: View {
    let model: DisplayModel

    var body: some View {
        SettingsCard(Text("Brightness", bundle: .module)) {
            if model.displays.isEmpty {
                Text("No display found.", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.displays) { display in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(display.name).lineLimit(1)
                        Spacer()
                        if !display.hasHardwareControl {
                            Text("dimmed by Sonary", bundle: .module).font(.caption2).foregroundStyle(.secondary)
                        } else if let dim = model.belowMinimum[display.id] {
                            Text("\(dim.formatted(.percent.precision(.fractionLength(0)))) below its minimum", bundle: .module)
                                .font(.caption2).foregroundStyle(.secondary)
                            Button { model.setBelowMinimum(0, for: display.id) } label: {
                                Text("Lift", bundle: .module).font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { display.brightness },
                                              set: { model.setBrightness($0, for: display.id) }), in: 0...1)
                        Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(display.name))
                }
            }
        }
        .task { model.refresh() }
    }
}

struct DisplaySettingsView: View {
    let model: DisplayModel

    var body: some View {
        SettingsCard(Text("Shortcuts", bundle: .module)) {
            SettingsToggleRow(symbol: "sun.max", title: Text("Brightness with ⌃⌥⇧↑ and ⌃⌥⇧↓", bundle: .module),
                              caption: Text("Changes the display the pointer is on.", bundle: .module),
                              isOn: Binding(get: { model.settings.shortcuts },
                                            set: { value in model.update { $0.shortcuts = value } }))
            SettingsRow(symbol: "slider.horizontal.3", title: Text("Step size", bundle: .module),
                        caption: Text("Finer steps for the shortcuts, like ⌥⇧ with the brightness keys.", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.stepSize },
                                          set: { value in model.update { $0.stepSize = value } })) {
                    Text("16 steps", bundle: .module).tag(BrightnessStepSize.normal)
                    Text("32 steps", bundle: .module).tag(BrightnessStepSize.fine)
                    Text("64 steps", bundle: .module).tag(BrightnessStepSize.finest)
                } label: { EmptyView() }
                    .labelsHidden()
                    .fixedSize()
            }
            SettingsToggleRow(symbol: "moon", title: Text("Go darker than the display's minimum", bundle: .module),
                              caption: Text("Stepping down past the lowest brightness keeps going with an overlay. Sonary lifts it again on restart.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.dimBelowMinimum },
                                            set: { value in model.update { $0.dimBelowMinimum = value } }))
        }
        if !model.extraBrightnessCapable.isEmpty {
            SettingsCard(Text("Extra brightness", bundle: .module)) {
                Text("These displays can go brighter than ordinary white. Sonary asks them to open that headroom, which is how XDR panels reach their peak.",
                     bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.displays.filter { model.extraBrightnessCapable.contains($0.id) }) { display in
                    SettingsRow(symbol: "sun.max.trianglebadge.exclamationmark", title: Text(display.name),
                                caption: Text("Brighter than white, which uses more power.", bundle: .module)) {
                        Slider(value: Binding(get: { model.extraBrightness(for: display.id) },
                                              set: { model.setExtraBrightness($0, for: display.id) }), in: 0...1)
                            .frame(width: 160)
                    }
                }
            }
        }
        if model.canSwitchBluetooth {
            SettingsCard(Text("Energy", bundle: .module)) {
                SettingsToggleRow(symbol: "bolt.horizontal",
                                  title: Text("Turn Bluetooth off while the Mac sleeps", bundle: .module),
                                  caption: Text("Switched back on when it wakes, and only if Sonary switched it off.",
                                                bundle: .module),
                                  isOn: Binding(get: { model.settings.bluetoothOffDuringSleep },
                                                set: { value in model.update { $0.bluetoothOffDuringSleep = value } }))
            }
        }
        SettingsCard(Text("Displays", bundle: .module)) {
            ForEach(model.displays) { display in
                SettingsRow(symbol: display.isBuiltIn ? "laptopcomputer" : "display",
                            title: Text(display.name),
                            caption: display.hasHardwareControl
                                ? Text("Hardware brightness", bundle: .module)
                                : Text("No hardware control: Sonary dims it with an overlay instead.", bundle: .module)) {
                    Text(verbatim: "\(Int((display.brightness * 100).rounded()))%")
                        .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if model.displays.isEmpty {
                Text("No display found.", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
        }
        .task { model.refresh() }
    }
}
