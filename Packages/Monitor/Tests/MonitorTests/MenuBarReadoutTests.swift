import Foundation
import Testing
@testable import Monitor

struct MenuBarReadoutTests {
    private func snapshot(battery: BatteryStats? = nil, temperatures: [String: Double] = [:],
                          network: NetworkRates = .zero) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: Date(timeIntervalSince1970: 0), cpu: 0.42, gpu: nil,
            memory: MemoryStats(usedBytes: 61, totalBytes: 100, pressure: .normal),
            network: network, disk: DiskStats(freeBytes: 1, totalBytes: 2),
            battery: battery, temperatures: temperatures
        )
    }

    @Test func formatReadoutJoinsSelectedMetrics() {
        #expect(formatReadout(snapshot(), metrics: [.cpu, .memory]) == "CPU 42% · RAM 61%")
    }

    @Test func formatReadoutShowsDashForMissingTemperature() {
        #expect(formatReadout(snapshot(), metrics: [.temperature]) == "TEMP —")
    }

    @Test func formatReadoutOmitsBatteryWhenNil() {
        #expect(formatReadout(snapshot(battery: nil), metrics: [.cpu, .battery]) == "CPU 42%")
    }

    @Test func formatReadoutFormatsNetworkAsHumanReadable() {
        let rates = NetworkRates(bytesInPerSec: 1_500_000, bytesOutPerSec: 200_000)
        #expect(formatReadout(snapshot(network: rates), metrics: [.network]) == "↓1.5 MB/s ↑200 KB/s")
    }
}

struct FanReadoutTests {
    private func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: Date(timeIntervalSince1970: 0), cpu: 0.4, gpu: nil,
            memory: MemoryStats(usedBytes: 50, totalBytes: 100, pressure: .normal),
            network: .zero, disk: DiskStats(freeBytes: 1, totalBytes: 2),
            battery: nil, temperatures: [:]
        )
    }

    @Test func showsTheFastestFan() {
        let text = formatReadout(snapshot(), metrics: [.fan], fans: [FanReading(index: 0, rpm: 2400)])
        #expect(text == "FAN 2400 rpm")
    }

    @Test func fanlessMacShowsNothing() {
        #expect(formatReadout(snapshot(), metrics: [.fan], fans: []).isEmpty)
        #expect(formatReadout(snapshot(), metrics: [.cpu, .fan], fans: []) == "CPU 40%")
    }
}

struct MonitorGapTests {
    private func snapshot(battery: BatteryStats? = BatteryStats(level: 0.8, isCharging: false)) -> MetricsSnapshot {
        MetricsSnapshot(timestamp: Date(timeIntervalSince1970: 0), cpu: 0.42, gpu: nil,
                        memory: MemoryStats(usedBytes: 61, totalBytes: 100, pressure: .normal),
                        network: .zero, disk: DiskStats(freeBytes: 50, totalBytes: 100), battery: battery,
                        temperatures: [:], diskIO: DiskRates(readPerSec: 1_500_000, writePerSec: 200_000))
    }

    @Test func barsReplaceTheNumbers() {
        #expect(formatReadout(snapshot(), metrics: [.cpu, .memory], bars: true) == "CPU ▄ · RAM ▅")
        #expect(usageBar(0) == "▁")
        #expect(usageBar(1) == "█")
    }

    @Test func batteryTimeAndDiskActivityShow() {
        #expect(formatReadout(snapshot(), metrics: [.battery], batteryTime: 11_100) == "BAT 80% 3:05")
        #expect(formatReadout(snapshot(), metrics: [.disk]) == "R 1.5 MB/s W 200 KB/s")
    }

    @Test func eachMetricHasItsOwnPiece() {
        let items = readoutItems(snapshot(battery: nil), metrics: [.cpu, .battery, .memory])
        #expect(items.map(\.metric) == [.cpu, .memory])
    }

    @Test func coresAndDiskRatesComeFromDeltas() {
        let before = [CPUTicks(user: 10, system: 0, idle: 90, nice: 0), CPUTicks(user: 0, system: 0, idle: 100, nice: 0)]
        let after = [CPUTicks(user: 60, system: 0, idle: 140, nice: 0), CPUTicks(user: 0, system: 0, idle: 200, nice: 0)]
        #expect(perCoreUsage(previous: before, current: after) == [0.5, 0])
        #expect(perCoreUsage(previous: [], current: after).isEmpty)
        let rates = diskRates(previous: DiskCounters(bytesRead: 100, bytesWritten: 50),
                              current: DiskCounters(bytesRead: 300, bytesWritten: 40), interval: 2)
        #expect(rates == DiskRates(readPerSec: 100, writePerSec: 0))
    }

    @Test func batteryDetailsReadTheRegistry() {
        let details = batteryDetails(["CycleCount": NSNumber(value: 312), "DesignCapacity": NSNumber(value: 5000),
                                      "AppleRawMaxCapacity": NSNumber(value: 4500), "Voltage": NSNumber(value: 12_000),
                                      "InstantAmperage": NSNumber(value: -1500)])
        #expect(details.cycles == 312)
        #expect(details.health == 0.9)
        #expect(details.watts == -18)
        #expect(batteryDetails([:]).health == nil)
    }

    @Test func usbDevicesSkipHubsAndRepeats() {
        let devices = parseUSBDevices([
            ["USB Product Name": "Keyboard", "USB Vendor Name": "Keychron", "locationID": NSNumber(value: 1)],
            ["USB Product Name": "USB2.0 Hub", "locationID": NSNumber(value: 2)],
            ["USB Product Name": "Keyboard", "locationID": NSNumber(value: 1)],
            ["USB Product Name": "Audio Interface", "locationID": NSNumber(value: 3)],
        ])
        #expect(devices.map(\.name) == ["Audio Interface", "Keyboard"])
        #expect(devices.last?.vendor == "Keychron")
    }
}

struct PowerTests {
    @Test func batteryAndChargerFiguresAreRead() {
        let battery: [String: Any] = ["Voltage": NSNumber(value: 12_500), "InstantAmperage": NSNumber(value: 2000),
                                      "Temperature": NSNumber(value: 3150), "DesignCapacity": NSNumber(value: 5000),
                                      "AppleRawMaxCapacity": NSNumber(value: 4600), "AppleRawCurrentCapacity": NSNumber(value: 2300),
                                      "ExternalConnected": true, "FullyCharged": false]
        let adapter: [String: Any] = ["Watts": NSNumber(value: 96), "Name": "96W USB-C Power Adapter"]
        let stats = powerStats(battery: battery, adapter: adapter, systemWatts: 18.4, adapterInputWatts: 43.0)
        #expect(stats.batteryWatts == 25)
        #expect(stats.batteryTemperature == 31.5)
        #expect(stats.voltage == 12.5)
        #expect(stats.fullCapacity == 4600)
        #expect(stats.adapterRatedWatts == 96)
        #expect(stats.adapterName == "96W USB-C Power Adapter")
        #expect(stats.systemWatts == 18.4)
        #expect(stats.isPluggedIn)
    }

    @Test func aDesktopWithoutBatteryStillHasItsDraw() {
        let stats = powerStats(battery: [:], adapter: [:], systemWatts: 7.2, adapterInputWatts: nil)
        #expect(stats.batteryWatts == nil)
        #expect(stats.systemWatts == 7.2)
        #expect(!stats.isEmpty)
        #expect(powerStats(battery: [:], adapter: [:], systemWatts: 0, adapterInputWatts: nil).isEmpty)
    }

    @Test func wattsAndTemperaturesReadWell() {
        #expect(formatWatts(18.44) == "18.4 W")
        #expect(formatWatts(140) == "140 W")
        #expect(formatTemperature(30, fahrenheit: false) == "30 °C")
        #expect(formatTemperature(30, fahrenheit: true) == "86 °F")
    }
}
