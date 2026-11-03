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

        let cpu = previousTicks.map { cpuUsage(previous: $0, current: ticks) } ?? 0
        let rates: NetworkRates
        if let previousNetwork, let previousTime {
            rates = networkRates(previous: previousNetwork, current: counters,
                                 interval: time.timeIntervalSince(previousTime))
        } else {
            rates = .zero
        }
        previousTicks = ticks
        previousNetwork = counters
        previousTime = time

        return MetricsSnapshot(
            timestamp: time,
            cpu: cpu,
            gpu: sources.gpuUsage(),
            memory: sources.memory(),
            network: rates,
            disk: sources.disk(),
            battery: sources.battery(),
            temperatures: sources.temperatures()
        )
    }
}
