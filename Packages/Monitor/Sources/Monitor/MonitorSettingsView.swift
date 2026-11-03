import SwiftUI

struct MonitorSettingsView: View {
    let module: MonitorModule

    var body: some View {
        Section("Menu bar") {
            ForEach(ReadoutMetric.allCases, id: \.self) { metric in
                Toggle(label(for: metric), isOn: Binding(
                    get: { module.readoutMetrics.contains(metric) },
                    set: { on in
                        var metrics = module.readoutMetrics.filter { $0 != metric }
                        if on { metrics.append(metric) }
                        module.setReadoutMetrics(ReadoutMetric.allCases.filter(metrics.contains))
                    }
                ))
            }
        }
        Section("Alerts") {
            Toggle("Notify me about high load, temperature, low disk space and low battery", isOn: Binding(
                get: { module.alertsEnabled },
                set: { on in Task { await module.setAlertsEnabled(on) } }
            ))
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
