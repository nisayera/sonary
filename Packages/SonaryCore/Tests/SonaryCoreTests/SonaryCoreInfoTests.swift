import Testing
@testable import SonaryCore

@Test func packageNameIsStable() {
    #expect(SonaryCoreInfo.name == "SonaryCore")
}
