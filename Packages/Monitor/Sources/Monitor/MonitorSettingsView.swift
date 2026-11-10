import SonaryUI
import SwiftUI

struct MonitorSettingsView: View {
    let module: MonitorModule

    var body: some View {
        SettingsCard(Text("Menu bar", bundle: .module)) {
            SettingsToggleRow(
                symbol: "menubar.rectangle",
                title: Text("Show values in the menu bar", bundle: .module),
                caption: Text("Next to the Sonary icon. Off shows only the icon.", bundle: .module),
                isOn: Binding(get: { module.showsMenuBarValues }, set: { module.setShowsMenuBarValues($0) })
            )
            if module.showsMenuBarValues {
                SettingsToggleRow(
                    symbol: "chart.bar.fill",
                    title: Text("Bars instead of numbers", bundle: .module),
                    caption: Text("CPU, memory and battery as a small bar.", bundle: .module),
                    isOn: Binding(get: { module.menuBarBars }, set: { module.setMenuBarBars($0) })
                )
                SettingsToggleRow(
                    symbol: "rectangle.split.3x1",
                    title: Text("Each value as its own item", bundle: .module),
                    caption: Text("Separate menu bar items you can rearrange with ⌘ and drag.", bundle: .module),
                    isOn: Binding(get: { module.separateMenuBarItems }, set: { module.setSeparateMenuBarItems($0) })
                )
                ForEach(ReadoutMetric.allCases, id: \.self) { metric in
                    SettingsToggleRow(
                        symbol: symbol(for: metric),
                        title: Text(label(for: metric), bundle: .module),
                        isOn: Binding(
                            get: { module.readoutMetrics.contains(metric) },
                            set: { on in
                                var metrics = module.readoutMetrics.filter { $0 != metric }
                                if on { metrics.append(metric) }
                                module.setReadoutMetrics(ReadoutMetric.allCases.filter(metrics.contains))
                            }
                        )
                    )
                }
            }
        }
        SettingsCard(Text("Readings", bundle: .module)) {
            SettingsRow(symbol: "timer", title: Text("Read every", bundle: .module),
                        caption: Text("Slower readings use a little less energy. The graphs always cover about five minutes.",
                                      bundle: .module)) {
                Picker(selection: Binding(get: { module.sampleInterval },
                                          set: { value in Task { await module.setSampleInterval(value) } })) {
                    Text(verbatim: "1 s").tag(1)
                    Text(verbatim: "2 s").tag(2)
                    Text(verbatim: "5 s").tag(5)
                } label: { EmptyView() }
                    .pickerStyle(.segmented).settingsControl()
            }
            SettingsToggleRow(symbol: "thermometer.medium", title: Text("Temperatures in Fahrenheit", bundle: .module),
                              isOn: Binding(get: { module.fahrenheit }, set: { module.setFahrenheit($0) }))
        }
        SettingsCard(Text("In the panel", bundle: .module)) {
            ForEach(MonitorSection.allCases) { section in
                SettingsToggleRow(symbol: sectionSymbol(section), title: Text(sectionTitle(section), bundle: .module),
                                  isOn: Binding(get: { module.shows(section) },
                                                set: { module.setSection(section, visible: $0) }))
            }
        }
        SettingsCard(Text("Alerts", bundle: .module)) {
            SettingsToggleRow(
                symbol: "bell.badge",
                title: Text("Notifications", bundle: .module),
                caption: Text("Notify me about high load, temperature, low disk space and low battery", bundle: .module),
                isOn: Binding(get: { module.alertsEnabled }, set: { on in Task { await module.setAlertsEnabled(on) } })
            )
        }
    }

    private func sectionTitle(_ section: MonitorSection) -> LocalizedStringKey {
        switch section {
        case .rings: "Rings for CPU, memory, disk and battery"
        case .power: "Power and battery"
        case .usage: "Usage over time"
        case .network: "Network"
        case .processes: "Busiest apps"
        case .usb: "USB devices"
        }
    }

    private func sectionSymbol(_ section: MonitorSection) -> String {
        switch section {
        case .rings: "circle.dashed"
        case .power: "bolt.fill"
        case .usage: "chart.xyaxis.line"
        case .network: "network"
        case .processes: "list.number"
        case .usb: "cable.connector"
        }
    }

    private func label(for metric: ReadoutMetric) -> LocalizedStringKey {
        switch metric {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk activity"
        case .power: "Power"
        case .battery: "Battery"
        case .temperature: "Temperature"
        case .fan: "Fan speed"
        }
    }

    private func symbol(for metric: ReadoutMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .power: "bolt"
        case .battery: "battery.75percent"
        case .temperature: "thermometer.medium"
        case .fan: "fan"
        }
    }
}
