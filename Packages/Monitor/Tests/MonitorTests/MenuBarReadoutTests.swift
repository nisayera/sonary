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
