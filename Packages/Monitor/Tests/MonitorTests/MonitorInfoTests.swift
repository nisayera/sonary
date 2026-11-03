import Testing
@testable import Monitor

@Test func packageNameIsStable() {
    #expect(MonitorInfo.name == "Monitor")
}
