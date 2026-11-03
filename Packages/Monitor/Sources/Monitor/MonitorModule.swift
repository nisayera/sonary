import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class MonitorModule: SonaryModule {
    public let id = "monitor"
    public let title = LocalizedStringResource("Monitor", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "gauge.with.dots.needle.67percent"
    public var requiredPermissions: [SonaryPermission] { [] }

    public private(set) var latest: MetricsSnapshot?
    public private(set) var history: [MetricsSnapshot] = []
    public private(set) var readoutMetrics: [ReadoutMetric]
    public private(set) var alertsEnabled: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sourcesFactory: @Sendable () -> any MetricsSources
    @ObservationIgnored private var sampler: MetricsSampler?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        sources: @escaping @Sendable () -> any MetricsSources = { SystemSources(sensors: SystemSensorReader()) }
    ) {
        self.defaults = defaults
        self.sourcesFactory = sources
        let stored = defaults.stringArray(forKey: "monitor.readout")?.compactMap(ReadoutMetric.init(rawValue:))
        self.readoutMetrics = stored ?? [.cpu, .memory]
        self.alertsEnabled = defaults.bool(forKey: "monitor.alerts")
    }

    public func start() async throws {
        guard task == nil else { return }
        let sampler = MetricsSampler(sources: sourcesFactory())
        self.sampler = sampler
        let stream = await sampler.snapshots()
        task = Task { [weak self] in
            var evaluator = AlertEvaluator()
            let notifier = AlertNotifier()
            for await snapshot in stream {
                guard let self else { return }
                let recent = await sampler.history()
                self.latest = snapshot
                self.history = recent
                let fired = evaluator.evaluate(snapshot)
                if self.alertsEnabled {
                    for kind in fired { await notifier.send(kind) }
                }
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        await sampler?.stop()
        sampler = nil
        latest = nil
        history = []
    }

    public func setReadoutMetrics(_ metrics: [ReadoutMetric]) {
        readoutMetrics = metrics
        defaults.set(metrics.map(\.rawValue), forKey: "monitor.readout")
    }

    public func setAlertsEnabled(_ enabled: Bool) async {
        if enabled {
            guard await AlertNotifier().requestAuthorization() else { return }
        }
        alertsEnabled = enabled
        defaults.set(enabled, forKey: "monitor.alerts")
    }

    public func menuBarText() -> String? {
        guard let latest, !readoutMetrics.isEmpty else { return nil }
        return formatReadout(latest, metrics: readoutMetrics)
    }

    public func makeSettingsView() -> AnyView { AnyView(MonitorSettingsView(module: self)) }
    public func makePopoverView() -> AnyView? { AnyView(MonitorView(module: self)) }
}
