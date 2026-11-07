import Charts
import Foundation
import SonaryUI
import SwiftUI

/// The monitor in the menu bar panel: a row of tiles for what is read as one number, bars with
/// a short history for what is a share of something, then network and the busiest apps.
public struct MonitorView: View {
    let module: MonitorModule
    /// The usage row opened to its longer graph, by title.
    @State private var expanded: String?

    public init(module: MonitorModule) {
        self.module = module
    }

    public var body: some View {
        if let latest = module.latest {
            let history = module.history
            VStack(alignment: .leading, spacing: PanelMetrics.spacing) {
                tiles(latest)
                usage(latest, history: history)
                network(latest, history: history)
                if let battery = latest.battery, battery.health != nil || battery.cycleCount != nil || battery.watts != nil {
                    batteryDetails(battery)
                }
                if !module.topProcesses.isEmpty {
                    busiest
                }
                if !module.usbDevices.isEmpty {
                    usb
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(Spacing.m)
        }
    }

    // MARK: - Blocks

    /// Rings for the shares at the top, then the values that are not shares.
    private func tiles(_ latest: MetricsSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                LabeledRing(Text(verbatim: "CPU"), fraction: latest.cpu, value: percentNumber(latest.cpu),
                            tint: ringTint(latest.cpu),
                            detail: latest.cores.isEmpty ? nil : Text("\(latest.cores.count) cores", bundle: .module))
                LabeledRing(Text("Memory", bundle: .module), fraction: latest.memory.usedFraction,
                            value: percentNumber(latest.memory.usedFraction), tint: pressureColor(latest.memory.pressure),
                            detail: Text(verbatim: formatBytes(latest.memory.usedBytes)))
                LabeledRing(Text("Disk", bundle: .module), fraction: 1 - latest.disk.freeFraction,
                            value: percentNumber(1 - latest.disk.freeFraction), tint: ringTint(1 - latest.disk.freeFraction),
                            detail: Text("\(formatBytes(latest.disk.freeBytes)) free", bundle: .module))
                if let battery = latest.battery {
                    LabeledRing(Text("Battery", bundle: .module), fraction: battery.level, value: percentNumber(battery.level),
                                tint: battery.isCharging ? .green : (battery.level < 0.2 ? .orange : .sonaryAccent),
                                detail: battery.isCharging ? Text("Charging", bundle: .module)
                                    : module.batteryTime.map { Text(verbatim: formatDuration($0)) })
                }
            }
            .padding(.vertical, 10)
            .panelCard(padded: false)
            otherTiles(latest)
        }
    }

    private func percentNumber(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private func ringTint(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .red : fraction >= 0.75 ? .orange : .sonaryAccent
    }

    private func otherTiles(_ latest: MetricsSnapshot) -> some View {
        HStack(spacing: 8) {
            MonitorTile(symbol: "thermometer.medium", title: "Temperature",
                        value: (latest.temperatures["CPU"] ?? latest.temperatures.values.max())
                            .map { "\(Int($0.rounded())) °C" } ?? "—",
                        detail: temperatureDetail(latest.temperatures))
            if let fastest = module.fans.map(\.rpm).max(), fastest > 0 {
                MonitorTile(symbol: "fan", title: "Fans", value: formatFanSpeed(module.fans))
            }
            MonitorTile(symbol: "network", title: "Network",
                        value: formatRate(latest.network.bytesInPerSec),
                        detail: "↑ " + formatRate(latest.network.bytesOutPerSec))
        }
    }

    private func usage(_ latest: MetricsSnapshot, history: [MetricsSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(Text("Usage", bundle: .module))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 10) {
                usageRow("CPU", fraction: latest.cpu, color: .sonaryAccent, series: history.map(\.cpu))
                if !latest.cores.isEmpty {
                    CoreBars(cores: latest.cores)
                }
                if let gpu = latest.gpu {
                    usageRow("GPU", fraction: gpu, color: .sonaryAccent, series: history.compactMap(\.gpu))
                }
                usageRow("Memory", fraction: latest.memory.usedFraction, color: pressureColor(latest.memory.pressure),
                         series: history.map(\.memory.usedFraction))
                UsageRow(title: "Disk", fraction: 1 - latest.disk.freeFraction, color: .secondary)
                HStack {
                    Label { Text(verbatim: formatRate(latest.diskIO.readPerSec)) } icon: { Image(systemName: "arrow.down.doc") }
                        .help(Text("Read", bundle: .module))
                    Spacer()
                    Label { Text(verbatim: formatRate(latest.diskIO.writePerSec)) } icon: { Image(systemName: "arrow.up.doc") }
                        .help(Text("Written", bundle: .module))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .panelCard()
        }
    }

    private func network(_ latest: MetricsSnapshot, history: [MetricsSnapshot]) -> some View {
        let incoming = history.map(\.network.bytesInPerSec)
        return VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(Text("Network", bundle: .module))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label { Text(verbatim: formatRate(latest.network.bytesInPerSec)) } icon: {
                        Image(systemName: "arrow.down")
                    }
                    Spacer()
                    Label { Text(verbatim: formatRate(latest.network.bytesOutPerSec)) } icon: {
                        Image(systemName: "arrow.up")
                    }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                if incoming.count > 1 {
                    Sparkline(series: incoming, domain: 0...max(1, incoming.max() ?? 1), color: .teal)
                }
                Divider()
                KeyValueRow(title: "Downloaded", value: formatBytes(module.totals.bytesIn))
                KeyValueRow(title: "Uploaded", value: formatBytes(module.totals.bytesOut))
                if let address = module.localAddress {
                    KeyValueRow(title: "Local address", value: address)
                }
                HStack {
                    Text("Connection speed", bundle: .module).foregroundStyle(.secondary)
                    Spacer()
                    if module.isSpeedTesting {
                        ProgressView().controlSize(.mini)
                    } else if let result = module.speedTest {
                        Text(verbatim: "\(formatThroughput(result.downloadBitsPerSecond)) · \(formatLatency(result.latency))")
                            .monospacedDigit()
                    } else {
                        Button { Task { await module.runSpeedTest() } } label: {
                            Text("Measure", bundle: .module)
                        }
                        .controlSize(.mini)
                    }
                }
                .font(.system(size: 11))
            }
            .panelCard()
        }
    }

    /// A usage row that opens to the whole history when clicked, and closes again.
    private func usageRow(_ title: String, fraction: Double, color: Color, series: [Double]) -> some View {
        UsageRow(title: LocalizedStringKey(title), fraction: fraction, color: color, series: series,
                 isExpanded: expanded == title)
            .contentShape(Rectangle())
            .onTapGesture { expanded = expanded == title ? nil : title }
    }

    private func temperatureDetail(_ temperatures: [String: Double]) -> String? {
        let parts = [("GPU", temperatures["GPU"]), ("BAT", temperatures["Battery"])].compactMap { label, value in
            value.map { "\(label) \(Int($0.rounded()))°" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func batteryDetails(_ battery: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(Text("Battery", bundle: .module))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 6) {
                if let health = battery.health {
                    KeyValueRow(title: "Health", value: percent(health))
                }
                if let cycles = battery.cycleCount {
                    KeyValueRow(title: "Charge cycles", value: "\(cycles)")
                }
                if let watts = battery.watts {
                    KeyValueRow(title: watts >= 0 ? "Charging with" : "Drawing",
                                value: String(format: "%.1f W", abs(watts)))
                }
            }
            .panelCard()
        }
    }

    private var usb: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(Text("USB devices", bundle: .module))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(module.usbDevices) { device in
                    HStack {
                        Text(verbatim: device.name).lineLimit(1)
                        Spacer()
                        if let vendor = device.vendor {
                            Text(verbatim: vendor).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                }
            }
            .panelCard()
        }
    }

    private var busiest: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(Text("Busiest apps", bundle: .module))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(module.topProcesses) { process in
                    HStack {
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text(verbatim: "\(Int(process.cpu.rounded())) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                }
            }
            .panelCard()
        }
    }

    // MARK: - Formatting

    private func pressureColor(_ pressure: MemoryStats.Pressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }
}

// MARK: - Pieces

/// One number with its name above it, on a slightly raised tile.
private struct MonitorTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    var detail: String?

    var body: some View {
        VStack(spacing: 3) {
            Label { Text(title, bundle: .module) } icon: { Image(systemName: symbol) }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let detail {
                Text(verbatim: detail)
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .panelCard(padded: false)
        .accessibilityElement(children: .combine)
    }
}

/// A share of something: name, bar, percentage, and the last few minutes under it.
private struct UsageRow: View {
    let title: LocalizedStringKey
    let fraction: Double
    let color: Color
    var series: [Double] = []
    /// Shows the whole history with a scale, instead of the thin line.
    var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title, bundle: .module)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 62, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PanelColors.control(colorScheme))
                        Capsule().fill(color)
                            .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 5)
                Text(verbatim: "\(Int((fraction * 100).rounded())) %")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            if series.count > 1 {
                if isExpanded {
                    DetailChart(series: series, color: color)
                } else {
                    Sparkline(series: series, domain: 0...1, color: color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The last few minutes as a thin line.
private struct Sparkline: View {
    let series: [Double]
    let domain: ClosedRange<Double>
    let color: Color

    var body: some View {
        Chart(Array(series.enumerated()), id: \.offset) { point in
            LineMark(x: .value("t", point.offset), y: .value("v", point.element))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

/// The whole history of one share, five minutes at one reading a second, with a scale.
private struct DetailChart: View {
    let series: [Double]
    let color: Color

    var body: some View {
        Chart(Array(series.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("t", point.offset), y: .value("v", point.element * 100))
                .foregroundStyle(color.opacity(0.18))
            LineMark(x: .value("t", point.offset), y: .value("v", point.element * 100))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0)%").font(.system(size: 8)) }
            }
        }
        .frame(height: 90)
        .accessibilityHidden(true)
    }
}

/// One thin bar per core, so a single busy core shows even when the average is low.
private struct CoreBars: View {
    let cores: [Double]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5).fill(PanelColors.control(colorScheme))
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.sonaryAccent)
                        .frame(height: max(1.5, 18 * min(max(load, 0), 1)))
                }
                .frame(height: 18)
            }
        }
        .padding(.leading, 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(cores.count) cores", bundle: .module))
    }
}

private struct KeyValueRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title, bundle: .module).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}
