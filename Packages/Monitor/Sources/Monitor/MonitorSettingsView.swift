import SwiftUI

struct MonitorSettingsView: View {
    let module: MonitorModule

    var body: some View {
        Section {
            ForEach(ReadoutMetric.allCases, id: \.self) { metric in
                Toggle(isOn: Binding(
                    get: { module.readoutMetrics.contains(metric) },
                    set: { on in
                        var metrics = module.readoutMetrics.filter { $0 != metric }
                        if on { metrics.append(metric) }
                        module.setReadoutMetrics(ReadoutMetric.allCases.filter(metrics.contains))
                    }
                )) {
                    Text(label(for: metric), bundle: .module)
                }
            }
        } header: {
            Text("Menu bar", bundle: .module)
        }
        Section {
            Toggle(isOn: Binding(
                get: { module.alertsEnabled },
                set: { on in Task { await module.setAlertsEnabled(on) } }
            )) {
                Text("Notify me about high load, temperature, low disk space and low battery", bundle: .module)
            }
        } header: {
            Text("Alerts", bundle: .module)
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
}
