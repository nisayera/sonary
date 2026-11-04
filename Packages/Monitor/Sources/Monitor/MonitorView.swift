import Foundation
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
                    if !module.topProcesses.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Busiest apps", bundle: .module).font(.headline)
                                ForEach(module.topProcesses) { process in
                                    HStack {
                                        Text(process.name).lineLimit(1)
                                        Spacer()
                                        Text(verbatim: "\(Int(process.cpu.rounded()))%")
                                            .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("This session", bundle: .module).font(.headline)
                                Spacer()
                            }
                            HStack {
                                Text("Downloaded", bundle: .module)
                                Spacer()
                                Text(verbatim: formatBytes(module.totals.bytesIn)).monospacedDigit()
                            }
                            HStack {
                                Text("Uploaded", bundle: .module)
                                Spacer()
                                Text(verbatim: formatBytes(module.totals.bytesOut)).monospacedDigit()
                            }
                            if let address = module.localAddress {
                                HStack {
                                    Text("Local address", bundle: .module)
                                    Spacer()
                                    Text(verbatim: address).monospacedDigit()
                                }
                            }
                            HStack {
                                Text("Connection speed", bundle: .module)
                                Spacer()
                                if module.isSpeedTesting {
                                    ProgressView().controlSize(.small)
                                } else if let result = module.speedTest {
                                    Text(verbatim: "\(formatThroughput(result.downloadBitsPerSecond)) · \(formatLatency(result.latency))")
                                        .monospacedDigit()
                                } else {
                                    Button { Task { await module.runSpeedTest() } } label: {
                                        Text("Measure", bundle: .module)
                                    }
                                    .controlSize(.small)
                                }
                            }
                            if let time = module.batteryTime {
                                HStack {
                                    Text("Battery left", bundle: .module)
                                    Spacer()
                                    Text(verbatim: formatDuration(time)).monospacedDigit()
                                }
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let fastest = module.fans.map(\.rpm).max(), fastest > 0 {
                        MetricCard(title: "Fans", value: formatFanSpeed(module.fans), symbol: "fan")
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

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
