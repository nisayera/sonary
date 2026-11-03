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
    @Test func germanCatalogResolvesMonitorStrings() throws {
        let path = try #require(MonitorBundle.bundle.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(german.localizedString(forKey: "Memory", value: nil, table: nil) == "Arbeitsspeicher")
        #expect(german.localizedString(forKey: "Menu bar", value: nil, table: nil) == "Menüleiste")
        #expect(german.localizedString(forKey: "Low battery", value: nil, table: nil) == "Akku fast leer")
    }
}
