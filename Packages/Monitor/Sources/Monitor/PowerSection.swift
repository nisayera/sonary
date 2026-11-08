import Charts
import SonaryUI
import SwiftUI

/// Where the power goes: the battery with its charge and state, the flow from charger to
/// Mac to battery, the last minutes of the Mac's draw, and the battery's own figures.
struct PowerSection: View {
    let latest: MetricsSnapshot
    let history: [MetricsSnapshot]
    let batteryTime: TimeInterval?
    let fahrenheit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let battery = latest.battery {
                batteryHeader(battery)
            }
            flow
            drawChart
            details
        }
        .panelCard()
    }

    // MARK: Battery

    private func batteryHeader(_ battery: BatteryStats) -> some View {
        HStack(spacing: 12) {
            BatteryGlyph(level: battery.level, charging: battery.isCharging,
                         pluggedIn: latest.power?.isPluggedIn ?? battery.isCharging)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(Int((battery.level * 100).rounded())) %")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                state(battery)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func state(_ battery: BatteryStats) -> Text {
        let power = latest.power
        if power?.isFullyCharged == true {
            return Text("Fully charged", bundle: .module)
        }
        if battery.isCharging {
            if let minutes = battery.minutesRemaining, minutes > 0 {
                return Text("Charging, full in \(formatDuration(TimeInterval(minutes * 60)))", bundle: .module)
            }
            return Text("Charging", bundle: .module)
        }
        if power?.isPluggedIn == true {
            return Text("Plugged in, not charging", bundle: .module)
        }
        if let left = batteryTime ?? battery.minutesRemaining.map({ TimeInterval($0 * 60) }) {
            return Text("On battery, \(formatDuration(left)) left", bundle: .module)
        }
        return Text("On battery", bundle: .module)
    }

    // MARK: Flow

    /// Charger, Mac and battery side by side, with the watts each one moves.
    @ViewBuilder
    private var flow: some View {
        let tiles = flowTiles
        if !tiles.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 3) {
                        IconBadge(symbol: tile.symbol, tint: tile.tint, size: 22)
                        Text(verbatim: tile.value)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        tile.title
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private struct FlowTile {
        let symbol: String
        let title: Text
        let value: String
        let tint: Color
    }

    private var flowTiles: [FlowTile] {
        var tiles: [FlowTile] = []
        let power = latest.power
        if let watts = power?.adapterWatts {
            tiles.append(FlowTile(symbol: "powerplug.fill", title: Text("Charger", bundle: .module),
                                  value: formatWatts(watts), tint: .green))
        }
        if let watts = power?.systemWatts {
            tiles.append(FlowTile(symbol: "desktopcomputer", title: Text("Mac", bundle: .module),
                                  value: formatWatts(watts), tint: .sonaryAccent))
        }
        if latest.battery != nil, let watts = power?.batteryWatts ?? latest.battery?.watts {
            tiles.append(FlowTile(symbol: watts >= 0 ? "battery.100.bolt" : "battery.50percent",
                                  title: Text("Battery", bundle: .module),
                                  value: (watts >= 0 ? "+" : "−") + formatWatts(abs(watts)),
                                  tint: watts >= 0 ? .green : .orange))
        }
        return tiles
    }

    // MARK: Chart

    /// The Mac's draw over the last minutes, when the SMC reports it.
    @ViewBuilder
    private var drawChart: some View {
        let series = history.compactMap { $0.power?.systemWatts }
        if series.count > 2 {
            let top = max(5, (series.max() ?? 5) * 1.15)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Power draw", bundle: .module).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "Ø " + formatWatts(series.reduce(0, +) / Double(series.count)))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
                Chart(Array(series.enumerated()), id: \.offset) { point in
                    AreaMark(x: .value("t", point.offset), y: .value("W", point.element))
                        .foregroundStyle(Color.sonaryAccent.opacity(0.18))
                    LineMark(x: .value("t", point.offset), y: .value("W", point.element))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .foregroundStyle(Color.sonaryAccent)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...top)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0) W").font(.system(size: 8)) }
                    }
                }
                .frame(height: 64)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        let rows = detailRows
        if !rows.isEmpty {
            Divider()
            VStack(spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0, bundle: .module).foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: row.1).monospacedDigit().lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }

    private var detailRows: [(LocalizedStringKey, String)] {
        let power = latest.power
        let battery = latest.battery
        var rows: [(LocalizedStringKey, String)] = []
        if let health = battery?.health { rows.append(("Health", "\(Int((health * 100).rounded())) %")) }
        if let cycles = battery?.cycleCount { rows.append(("Charge cycles", "\(cycles)")) }
        if let capacity = capacity(power) { rows.append(("Capacity", capacity)) }
        if let temperature = power?.batteryTemperature {
            rows.append(("Battery temperature", formatTemperature(temperature, fahrenheit: fahrenheit)))
        }
        if let volts = power?.voltage { rows.append(("Voltage", String(format: "%.2f V", volts))) }
        if let rated = power?.adapterRatedWatts {
            let name = [power?.adapterName, formatWatts(rated)].compactMap { $0 }.joined(separator: " · ")
            rows.append(("Charger", name))
        }
        return rows
    }

    private func capacity(_ power: PowerStats?) -> String? {
        guard let full = power?.fullCapacity, full > 0 else { return nil }
        if let design = power?.designCapacity, design > 0 {
            return "\(full) / \(design) mAh"
        }
        return "\(full) mAh"
    }
}

/// A battery drawn as a battery: its outline, the charge filling it, a bolt while charging.
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    let pluggedIn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fill: Color = charging || pluggedIn ? .green : level < 0.2 ? .red : level < 0.35 ? .orange : .sonaryAccent
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(fill.gradient)
                        .frame(width: max(4, (proxy.size.width - 6) * min(max(level, 0), 1)))
                        .padding(3)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 58, height: 30)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 3, height: 11)
        }
        .accessibilityHidden(true)
    }
}
