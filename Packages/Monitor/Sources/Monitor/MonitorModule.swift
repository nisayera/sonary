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
    /// Off by default: the menu bar shows the Sonary icon, values only when the user asks for them.
    public private(set) var showsMenuBarValues: Bool
    public private(set) var totals = NetworkTotals()
    public private(set) var topProcesses: [ProcessUsage] = []
    public private(set) var fans: [FanReading] = []
    public private(set) var localAddress: String?
    public private(set) var speedTest: SpeedTestResult?
    public private(set) var isSpeedTesting = false
    /// Rough time left on battery while it is discharging.
    public private(set) var batteryTime: TimeInterval?
    /// Shares in the menu bar as small bars instead of numbers.
    public private(set) var menuBarBars: Bool
    /// Each metric as a menu bar item of its own.
    public private(set) var separateMenuBarItems: Bool
    public private(set) var usbDevices: [USBDevice] = []
    @ObservationIgnored private let statusItems = MonitorStatusItems()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sourcesFactory: @Sendable () -> any MetricsSources
    @ObservationIgnored private var sampler: MetricsSampler?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var batterySamples: [(level: Double, at: Date)] = []

    @ObservationIgnored private let fanSource: any FanSource

    public init(
        defaults: UserDefaults = .standard,
        sources: @escaping @Sendable () -> any MetricsSources = { SystemSources(sensors: SystemSensorReader()) },
        fans: any FanSource = SMCFanReader()
    ) {
        self.fanSource = fans
        self.defaults = defaults
        self.sourcesFactory = sources
        let stored = defaults.stringArray(forKey: "monitor.readout")?.compactMap(ReadoutMetric.init(rawValue:))
        self.readoutMetrics = stored ?? [.cpu, .memory]
        self.alertsEnabled = defaults.bool(forKey: "monitor.alerts")
        self.showsMenuBarValues = defaults.bool(forKey: "monitor.menubar.values")
        self.menuBarBars = defaults.bool(forKey: "monitor.menubar.bars")
        self.separateMenuBarItems = defaults.bool(forKey: "monitor.menubar.separate")
    }

    public func start() async throws {
        guard sampler == nil else { return }
        let sampler = MetricsSampler(sources: sourcesFactory())
        self.sampler = sampler
        let stream = await sampler.snapshots()
        guard self.sampler === sampler else { return }
        localAddress = preferredLocalAddress(systemLocalAddresses())
        processTask = Task { [weak self] in
            while !Task.isCancelled {
                let source = self?.fanSource ?? NoFans()
                let readings = await Task.detached {
                    (processes: systemTopProcesses(limit: 5), fans: source.fans(), usb: systemUSBDevices())
                }.value
                guard let self else { return }
                self.topProcesses = readings.processes
                self.fans = readings.fans
                self.usbDevices = readings.usb
                try? await Task.sleep(for: .seconds(5))
            }
        }
        task = Task { [weak self] in
            var evaluator = AlertEvaluator()
            let notifier = AlertNotifier()
            for await snapshot in stream {
                guard let self else { return }
                let recent = await sampler.history()
                let totals = await sampler.totals()
                self.latest = snapshot
                self.history = recent
                self.totals = totals
                self.noteBattery(snapshot)
                self.updateStatusItems()
                let fired = evaluator.evaluate(snapshot)
                if self.alertsEnabled {
                    for kind in fired { await notifier.send(kind) }
                }
            }
        }
    }

    /// Keeps a few minutes of battery readings and estimates the time left from them.
    private func noteBattery(_ snapshot: MetricsSnapshot) {
        guard let battery = snapshot.battery, !battery.isCharging else {
            batterySamples = []
            batteryTime = nil
            return
        }
        batterySamples.append((level: battery.level, at: snapshot.timestamp))
        let cutoff = snapshot.timestamp.addingTimeInterval(-900)
        batterySamples.removeAll { $0.at < cutoff }
        batteryTime = batteryTimeRemaining(levels: batterySamples, now: snapshot.timestamp)
    }

    public func stop() async {
        statusItems.removeAll()
        processTask?.cancel()
        processTask = nil
        topProcesses = []
        fans = []
        task?.cancel()
        task = nil
        await sampler?.stop()
        sampler = nil
        latest = nil
        history = []
    }

    /// Measures the connection on demand. This is the only network call Sonary makes
    /// besides the update check, and it only happens when the user asks for it.
    public func runSpeedTest() async {
        guard !isSpeedTesting else { return }
        isSpeedTesting = true
        defer { isSpeedTesting = false }
        speedTest = try? await Monitor.runSpeedTest()
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

    public func setShowsMenuBarValues(_ show: Bool) {
        showsMenuBarValues = show
        defaults.set(show, forKey: "monitor.menubar.values")
        updateStatusItems()
    }

    public func setMenuBarBars(_ on: Bool) {
        menuBarBars = on
        defaults.set(on, forKey: "monitor.menubar.bars")
        updateStatusItems()
    }

    public func setSeparateMenuBarItems(_ on: Bool) {
        separateMenuBarItems = on
        defaults.set(on, forKey: "monitor.menubar.separate")
        updateStatusItems()
    }

    /// The values next to the Sonary icon; nil when they are off or have items of their own.
    public func menuBarText() -> String? {
        guard showsMenuBarValues, !separateMenuBarItems, let latest, !readoutMetrics.isEmpty else { return nil }
        return formatReadout(latest, metrics: readoutMetrics, fans: fans, bars: menuBarBars, batteryTime: batteryTime)
    }

    private func updateStatusItems() {
        guard showsMenuBarValues, separateMenuBarItems, let latest else {
            statusItems.removeAll()
            return
        }
        statusItems.show(readoutItems(latest, metrics: readoutMetrics, fans: fans, bars: menuBarBars,
                                      batteryTime: batteryTime))
    }

    public func makeSettingsView() -> AnyView { AnyView(MonitorSettingsView(module: self)) }
    public var resourceBundle: Bundle? { .module }

    public var status: [ModuleStatus] {
        guard let latest else { return [] }
        let memory = latest.memory.usedFraction
        var items = [
            ModuleStatus(id: "cpu", symbol: "cpu", title: "CPU", value: percentText(latest.cpu), fraction: latest.cpu,
                         level: loadLevel(latest.cpu, warning: 0.8, critical: 0.95)),
            ModuleStatus(id: "memory", symbol: "memorychip", title: String(localized: "Memory", bundle: .module),
                         value: percentText(memory), fraction: memory,
                         level: latest.memory.pressure == .critical ? .critical
                             : latest.memory.pressure == .warning ? .warning : .normal),
        ]
        if let battery = latest.battery {
            let low = !battery.isCharging && battery.level < 0.2
            items.append(ModuleStatus(id: "battery", symbol: battery.isCharging ? "battery.100.bolt" : "battery.75percent",
                                      title: String(localized: "Battery", bundle: .module),
                                      value: percentText(battery.level), fraction: battery.level,
                                      level: low ? (battery.level < 0.1 ? .critical : .warning) : .normal))
        }
        if let temperature = latest.temperatures["CPU"] ?? latest.temperatures.values.max() {
            items.append(ModuleStatus(id: "temperature", symbol: "thermometer.medium",
                                      title: String(localized: "Temperature", bundle: .module),
                                      value: "\(Int(temperature.rounded())) °C",
                                      level: temperature >= 95 ? .critical : temperature >= 85 ? .warning : .normal))
        }
        return items
    }
    public func makePopoverView() -> AnyView? { AnyView(MonitorView(module: self)) }
}
