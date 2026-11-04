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
