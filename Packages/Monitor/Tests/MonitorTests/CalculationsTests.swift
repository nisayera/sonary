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
