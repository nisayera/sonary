import Foundation

public actor MetricsSampler {
    private let sources: any MetricsSources
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    private var buffer: RingBuffer<MetricsSnapshot>
    private var continuations: [UUID: AsyncStream<MetricsSnapshot>.Continuation] = [:]
    private var loop: Task<Void, Never>?
    private var previousTicks: CPUTicks?
    private var previousNetwork: NetworkCounters?
    private var previousTime: Date?
    private var previousCores: [CPUTicks] = []
    private var previousDisk: DiskCounters?
    private var sessionTotals = NetworkTotals()

    public init(
        sources: any MetricsSources,
        interval: Duration = .seconds(1),
        capacity: Int = 300,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.interval = interval
        self.sleep = sleep
        self.now = now
        self.buffer = RingBuffer(capacity: capacity)
    }

    /// Subscribes to snapshots. The first call starts the sampling loop; the first snapshot is emitted immediately.
    public func snapshots() -> AsyncStream<MetricsSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<MetricsSnapshot>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        if loop == nil {
            loop = Task { await self.run() }
        }
        return stream
    }

    public func history() -> [MetricsSnapshot] { buffer.elements }

    /// Bytes in and out since this sampler started.
    public func totals() -> NetworkTotals { sessionTotals }

    public func stop() {
        loop?.cancel()
        loop = nil
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    // MARK: - Private

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func run() async {
        while !Task.isCancelled {
            let snapshot = takeSnapshot()
            buffer.append(snapshot)
            for continuation in continuations.values { continuation.yield(snapshot) }
            do { try await sleep(interval) } catch { return }
        }
    }

    private func takeSnapshot() -> MetricsSnapshot {
        let time = now()
        let ticks = sources.cpuTicks()
        let counters = sources.networkCounters()

        let cores = sources.coreTicks()
        let diskCounters = sources.diskCounters()

        let cpu = previousTicks.map { cpuUsage(previous: $0, current: ticks) } ?? 0
        let coreUsage = perCoreUsage(previous: previousCores, current: cores)
        let rates: NetworkRates
        var disk = DiskRates.zero
        if let previousNetwork, let previousTime {
            let interval = time.timeIntervalSince(previousTime)
            rates = networkRates(previous: previousNetwork, current: counters, interval: interval)
            sessionTotals.add(previous: previousNetwork, current: counters)
            if let previousDisk, let diskCounters {
                disk = diskRates(previous: previousDisk, current: diskCounters, interval: interval)
            }
        } else {
            rates = .zero
        }
        previousTicks = ticks
        previousNetwork = counters
        previousTime = time
        previousCores = cores
        previousDisk = diskCounters

        return MetricsSnapshot(
            timestamp: time,
            cpu: cpu,
            gpu: sources.gpuUsage(),
            memory: sources.memory(),
            network: rates,
            disk: sources.disk(),
            battery: sources.battery(),
            temperatures: sources.temperatures(),
            cores: coreUsage,
            diskIO: disk,
            power: sources.power()
        )
    }
}
