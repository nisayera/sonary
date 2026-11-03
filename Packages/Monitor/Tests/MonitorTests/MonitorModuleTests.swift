import Foundation
import Testing
@testable import Monitor

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor
struct MonitorModuleTests {
    @Test func concurrentStartCreatesOnlyOneSampler() async throws {
        let counter = CallCounter()
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 0)
        let module = MonitorModule(
            defaults: UserDefaults(suiteName: "sonary.monitortests.\(UUID().uuidString)")!,
            sources: {
                counter.increment()
                return FakeSources(ticks: [ticks], counters: [NetworkCounters(bytesIn: 0, bytesOut: 0)])
            }
        )
        async let first: Void = module.start()
        async let second: Void = module.start()
        try await first
        try await second
        #expect(counter.value == 1)
        await module.stop()
    }
}

struct MonitorLocalizationTests {
    /// `swift test` does not compile String Catalogs into .lproj folders, so the catalog source is checked directly.
    private func germanValue(for key: String) throws -> String? {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Monitor/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = json?["strings"] as? [String: Any]
        let entry = strings?[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let german = localizations?["de"] as? [String: Any]
        return (german?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    @Test func germanCatalogHasMonitorStrings() throws {
        #expect(try germanValue(for: "Memory") == "Arbeitsspeicher")
        #expect(try germanValue(for: "Menu bar") == "Menüleiste")
        #expect(try germanValue(for: "Low battery") == "Akku fast leer")
        #expect(try germanValue(for: "Alerts") == "Warnungen")
    }
}
