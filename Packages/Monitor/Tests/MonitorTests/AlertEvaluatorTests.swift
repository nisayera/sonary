import Foundation
import Testing
@testable import Monitor

struct AlertEvaluatorTests {
    private func snapshot(
        at seconds: TimeInterval, cpu: Double = 0.1,
        temperatures: [String: Double] = [:],
        pressure: MemoryStats.Pressure = .normal,
        disk: DiskStats = DiskStats(freeBytes: 50, totalBytes: 100),
        battery: BatteryStats? = nil
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: Date(timeIntervalSince1970: seconds), cpu: cpu, gpu: nil,
            memory: MemoryStats(usedBytes: 1, totalBytes: 2, pressure: pressure),
            network: .zero, disk: disk, battery: battery, temperatures: temperatures
        )
    }

    @Test func cpuAlertOnlyAfterSustainedDuration() {
        var evaluator = AlertEvaluator()
        for second in 0..<30 {
            #expect(evaluator.evaluate(snapshot(at: TimeInterval(second), cpu: 0.95)).isEmpty)
        }
        #expect(evaluator.evaluate(snapshot(at: 30, cpu: 0.95)) == [.sustainedCPU])
    }

    @Test func alertFiresOncePerEpisode() {
        var evaluator = AlertEvaluator()
        var thresholds = AlertThresholds()
        thresholds.cooldown = 2
        evaluator = AlertEvaluator(thresholds: thresholds)
        #expect(evaluator.evaluate(snapshot(at: 0, temperatures: ["CPU": 105])) == [.highTemperature])
        #expect(evaluator.evaluate(snapshot(at: 1, temperatures: ["CPU": 105])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 2, temperatures: ["CPU": 50])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 3, temperatures: ["CPU": 105])) == [.highTemperature])
    }

    @Test func lowBatteryIgnoredWhenChargingOrNoBattery() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, battery: nil)).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 1, battery: BatteryStats(level: 0.1, isCharging: true))).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 2, battery: BatteryStats(level: 0.1, isCharging: false))) == [.lowBattery])
    }

    @Test func highTemperatureUsesMaxOfSensors() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, temperatures: ["CPU": 60, "GPU": 101])) == [.highTemperature])
    }

    @Test func flappingAroundThresholdFiresOnceWithinCooldown() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, temperatures: ["CPU": 105])) == [.highTemperature])
        #expect(evaluator.evaluate(snapshot(at: 5, temperatures: ["CPU": 90])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 10, temperatures: ["CPU": 105])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 15, temperatures: ["CPU": 90])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 20, temperatures: ["CPU": 105])).isEmpty)
    }

    @Test func alertFiresAgainAfterCooldown() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, temperatures: ["CPU": 105])) == [.highTemperature])
        #expect(evaluator.evaluate(snapshot(at: 60, temperatures: ["CPU": 90])).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 601, temperatures: ["CPU": 105])) == [.highTemperature])
    }

    @Test func defaultTemperatureThresholdIs100() {
        #expect(AlertThresholds().temperature == 100)
    }

    @Test func memoryPressureCriticalFires() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, pressure: .warning)).isEmpty)
        #expect(evaluator.evaluate(snapshot(at: 1, pressure: .critical)) == [.memoryPressure])
    }

    @Test func lowDiskFiresBelowThreshold() {
        var evaluator = AlertEvaluator()
        #expect(evaluator.evaluate(snapshot(at: 0, disk: DiskStats(freeBytes: 4, totalBytes: 100))) == [.lowDisk])
    }
}
