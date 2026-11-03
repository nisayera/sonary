import Foundation
import Testing
@testable import Monitor

actor Ticker {
    private var permits = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { permits += 1 } else { waiters.removeFirst().resume() }
    }
}

final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0
    func now() -> Date { lock.withLock { seconds += 1; return Date(timeIntervalSince1970: seconds) } }
}

final class FakeSources: MetricsSources, @unchecked Sendable {
    private let lock = NSLock()
    private var tickQueue: [CPUTicks]
    private var counterQueue: [NetworkCounters]
    let batteryValue: BatteryStats?

    init(ticks: [CPUTicks], counters: [NetworkCounters], battery: BatteryStats? = nil) {
        self.tickQueue = ticks
        self.counterQueue = counters
        self.batteryValue = battery
    }

    private func pop<T>(_ queue: inout [T]) -> T { queue.count > 1 ? queue.removeFirst() : queue[0] }

    func cpuTicks() -> CPUTicks { lock.withLock { pop(&tickQueue) } }
    func networkCounters() -> NetworkCounters { lock.withLock { pop(&counterQueue) } }
    func gpuUsage() -> Double? { nil }
    func memory() -> MemoryStats { MemoryStats(usedBytes: 4, totalBytes: 8, pressure: .normal) }
    func disk() -> DiskStats { DiskStats(freeBytes: 1, totalBytes: 2) }
    func battery() -> BatteryStats? { batteryValue }
    func temperatures() -> [String: Double] { [:] }
}

struct MetricsSamplerTests {
    private func makeSampler(_ sources: FakeSources, capacity: Int = 300, ticker: Ticker = Ticker()) -> (MetricsSampler, Ticker) {
        let clock = StepClock()
        let sampler = MetricsSampler(
            sources: sources, capacity: capacity,
            sleep: { _ in await ticker.wait() },
            now: { clock.now() }
        )
        return (sampler, ticker)
    }

    private let t1 = CPUTicks(user: 100, system: 50, idle: 200, nice: 0)
    private let t2 = CPUTicks(user: 130, system: 60, idle: 260, nice: 0)
    private let c1 = NetworkCounters(bytesIn: 1_000, bytesOut: 500)
    private let c2 = NetworkCounters(bytesIn: 3_000, bytesOut: 1_500)

    @Test func firstSnapshotHasZeroCPUAndZeroNetwork() async {
        let (sampler, _) = makeSampler(FakeSources(ticks: [t1], counters: [c1]))
        var iterator = await sampler.snapshots().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.cpu == 0)
        #expect(first?.network == .zero)
        await sampler.stop()
    }

    @Test func secondSnapshotUsesTickDelta() async {
        let (sampler, ticker) = makeSampler(FakeSources(ticks: [t1, t2], counters: [c1, c2]))
        var iterator = await sampler.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        await ticker.release()
        let second = await iterator.next()
        #expect(abs((second?.cpu ?? -1) - 0.4) < 1e-9)
        #expect(second?.network == NetworkRates(bytesInPerSec: 2_000, bytesOutPerSec: 1_000))
        await sampler.stop()
    }

    @Test func historyCappedAtCapacity() async {
        let (sampler, ticker) = makeSampler(FakeSources(ticks: [t1, t2], counters: [c1, c2]), capacity: 2)
        var iterator = await sampler.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        for _ in 0..<2 {
            await ticker.release()
            _ = await iterator.next()
        }
        #expect(await sampler.history().count == 2)
        await sampler.stop()
    }

    @Test func batteryNilPassesThrough() async {
        let (sampler, _) = makeSampler(FakeSources(ticks: [t1], counters: [c1], battery: nil))
        var iterator = await sampler.snapshots().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
        #expect(first?.battery == nil)
        await sampler.stop()
    }

    @Test func stopFinishesStream() async {
        let (sampler, _) = makeSampler(FakeSources(ticks: [t1], counters: [c1]))
        var iterator = await sampler.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        await sampler.stop()
        #expect(await iterator.next() == nil)
    }
}
