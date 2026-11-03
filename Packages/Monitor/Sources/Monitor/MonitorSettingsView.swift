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
                Divider()
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
        SettingsCard(Text("Alerts", bundle: .module)) {
            SettingsToggleRow(
                symbol: "bell.badge",
                title: Text("Notifications", bundle: .module),
                caption: Text("Notify me about high load, temperature, low disk space and low battery", bundle: .module),
                isOn: Binding(get: { module.alertsEnabled }, set: { on in Task { await module.setAlertsEnabled(on) } })
            )
        }
    }

    private func label(for metric: ReadoutMetric) -> LocalizedStringKey {
        switch metric {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .battery: "Battery"
        case .temperature: "Temperature"
        }
    }

    private func symbol(for metric: ReadoutMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .battery: "battery.75percent"
        case .temperature: "thermometer.medium"
        }
    }
}
