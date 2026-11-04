import Foundation
import Testing
@testable import Monitor

struct CalculationsTests {
    @Test func ringBufferDropsOldestAtCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        #expect(buffer.elements == [3, 4, 5])
    }

    @Test func cpuUsageIsBusyShareOfDelta() {
        let a = CPUTicks(user: 100, system: 50, idle: 200, nice: 0)
        let b = CPUTicks(user: 130, system: 60, idle: 260, nice: 0)
        #expect(abs(cpuUsage(previous: a, current: b) - 0.4) < 1e-9)
    }

    @Test func cpuUsageIsZeroForIdenticalTicks() {
        let a = CPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        let value = cpuUsage(previous: a, current: a)
        #expect(value == 0)
        #expect(!value.isNaN)
    }

    @Test func networkRatesDivideByInterval() {
        let a = NetworkCounters(bytesIn: 1_000, bytesOut: 500)
        let b = NetworkCounters(bytesIn: 3_000, bytesOut: 1_500)
        let rates = networkRates(previous: a, current: b, interval: 2)
        #expect(rates == NetworkRates(bytesInPerSec: 1_000, bytesOutPerSec: 500))
    }

    @Test func networkRatesNeverNegativeWhenCounterResets() {
        let a = NetworkCounters(bytesIn: 9_000, bytesOut: 9_000)
        let b = NetworkCounters(bytesIn: 100, bytesOut: 100)
        #expect(networkRates(previous: a, current: b, interval: 1) == .zero)
    }

    @Test func networkRatesZeroForZeroInterval() {
        let a = NetworkCounters(bytesIn: 1, bytesOut: 1)
        let b = NetworkCounters(bytesIn: 9, bytesOut: 9)
        #expect(networkRates(previous: a, current: b, interval: 0) == .zero)
    }
}

struct TickCountTests {
    @Test func tickCountTreatsNegativeRawValuesAsWrappedUnsigned() {
        #expect(tickCount(-1) == 4_294_967_295)
        #expect(tickCount(Int32.min) == 2_147_483_648)
        #expect(tickCount(5) == 5)
    }
}

struct SessionTotalsTests {
    @Test func countsTheStepBetweenReadings() {
        var totals = NetworkTotals()
        totals.add(previous: NetworkCounters(bytesIn: 100, bytesOut: 50),
                   current: NetworkCounters(bytesIn: 400, bytesOut: 150))
        #expect(totals == NetworkTotals(bytesIn: 300, bytesOut: 100))
    }

    @Test func countersGoingBackwardsAddNothing() {
        var totals = NetworkTotals(bytesIn: 1_000, bytesOut: 1_000)
        totals.add(previous: NetworkCounters(bytesIn: 4_000_000_000, bytesOut: 4_000_000_000),
                   current: NetworkCounters(bytesIn: 12, bytesOut: 12))
        #expect(totals == NetworkTotals(bytesIn: 1_000, bytesOut: 1_000))
    }

    @Test func totalsAddUpOverManySteps() {
        var totals = NetworkTotals()
        for step in 0..<10 {
            totals.add(previous: NetworkCounters(bytesIn: UInt64(step * 10), bytesOut: 0),
                       current: NetworkCounters(bytesIn: UInt64(step * 10 + 10), bytesOut: 0))
        }
        #expect(totals.bytesIn == 100)
    }
}

struct ProcessUsageTests {
    private let sample = """
     123  12.5 /Applications/Safari.app/Contents/MacOS/Safari
     456   3.0 /usr/libexec/secd
     789  44.2 /Applications/Xcode.app/Contents/MacOS/Xcode
    """

    @Test func busiestFirstWithPlainNames() {
        let result = parseProcessUsage(sample, limit: 2)
        #expect(result.map(\.name) == ["Xcode", "Safari"])
        #expect(result.first?.cpu == 44.2)
    }

    @Test func skipsOurOwnProcess() {
        #expect(!parseProcessUsage(sample, limit: 5, excluding: 789).contains { $0.pid == 789 })
    }

    @Test func ignoresBrokenLines() {
        #expect(parseProcessUsage("nonsense\n\n  12 x /bin/zsh", limit: 5).isEmpty)
    }

    @Test func limitIsRespected() {
        #expect(parseProcessUsage(sample, limit: 1).count == 1)
        #expect(parseProcessUsage(sample, limit: 0).isEmpty)
    }
}

struct BatteryTimeTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func estimatesFromTheDrop() throws {
        let levels = [(level: 1.0, at: start), (level: 0.9, at: start.addingTimeInterval(600))]
        let remaining = try #require(batteryTimeRemaining(levels: levels, now: start.addingTimeInterval(600)))
        #expect(abs(remaining - 5400) < 1)
    }

    @Test func needsEnoughTimeAndADrop() {
        #expect(batteryTimeRemaining(levels: [(1.0, start)], now: start) == nil)
        #expect(batteryTimeRemaining(levels: [(1.0, start), (1.0, start.addingTimeInterval(600))], now: start) == nil)
        #expect(batteryTimeRemaining(levels: [(0.5, start), (0.4, start.addingTimeInterval(10))], now: start) == nil)
    }

    @Test func chargingGivesNoEstimate() {
        let levels = [(level: 0.4, at: start), (level: 0.6, at: start.addingTimeInterval(600))]
        #expect(batteryTimeRemaining(levels: levels, now: start) == nil)
    }

    @Test func durationReadsNaturally() {
        #expect(formatDuration(2700) == "45 min")
        #expect(formatDuration(7500) == "2 h 05 min")
    }
}

struct LocalAddressTests {
    @Test func prefersTheBuiltInInterface() {
        let addresses = [(interface: "utun4", address: "10.8.0.2"), (interface: "en0", address: "192.168.1.20")]
        #expect(preferredLocalAddress(addresses) == "192.168.1.20")
    }

    @Test func fallsBackToAnythingReal() {
        #expect(preferredLocalAddress([(interface: "bridge0", address: "192.168.64.1")]) == "192.168.64.1")
        #expect(preferredLocalAddress([(interface: "lo0", address: "127.0.0.1")]) == nil)
        #expect(preferredLocalAddress([]) == nil)
    }
}

@Suite struct SpeedTestLogicTests {
    @Test func refusesAMeasurementThatCannotMeanAnything() {
        #expect(throughput(bytes: 1000, seconds: 0) == nil)
        #expect(throughput(bytes: 1000, seconds: 0.001) == nil)
        #expect(throughput(bytes: 0, seconds: 2) == nil)
    }

    @Test func turnsBytesAndSecondsIntoBits() {
        #expect(throughput(bytes: 1_000_000, seconds: 1) == 8_000_000)
        #expect(throughput(bytes: 1_000_000, seconds: 2) == 4_000_000)
    }

    @Test func readsThroughputTheWayAPersonWould() {
        #expect(formatThroughput(94_300_000).hasSuffix("Mbit/s"))
        #expect(formatThroughput(94_300_000).hasPrefix("94.3"))
        #expect(formatThroughput(2_400_000_000).hasSuffix("Gbit/s"))
        #expect(formatLatency(0.0184) == "18 ms")
    }
}
