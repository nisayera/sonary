import SonaryUI
import SwiftUI

public struct MonitorView: View {
    let module: MonitorModule

    public init(module: MonitorModule) {
        self.module = module
    }

    public var body: some View {
        if let latest = module.latest {
            let history = module.history
            GlassEffectContainer(spacing: Spacing.s) {
                VStack(spacing: Spacing.s) {
                    MetricCard(title: "CPU", value: percent(latest.cpu), symbol: "cpu", series: history.map(\.cpu))
                    MetricCard(title: "GPU", value: latest.gpu.map(percent) ?? "—", symbol: "display",
                               series: history.compactMap(\.gpu))
                    MetricCard(title: "Memory", value: percent(latest.memory.usedFraction), symbol: "memorychip",
                               series: history.map(\.memory.usedFraction))
                    MetricCard(title: "Network", value: "↓\(formatRate(latest.network.bytesInPerSec))",
                               symbol: "network", series: history.map(\.network.bytesInPerSec),
                               domain: 0...max(1, history.map(\.network.bytesInPerSec).max() ?? 1))
                    MetricCard(title: "Disk", value: percent(1 - latest.disk.freeFraction), symbol: "internaldrive")
                    if let battery = latest.battery {
                        MetricCard(title: "Battery", value: percent(battery.level),
                                   symbol: battery.isCharging ? "battery.100.bolt" : "battery.75percent")
                    }
                    MetricCard(title: "Temperature",
                               value: latest.temperatures.values.max().map { "\(Int($0.rounded()))°" } ?? "—",
                               symbol: "thermometer.medium")
                }
            }
        } else {
            ProgressView().padding(Spacing.m)
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
