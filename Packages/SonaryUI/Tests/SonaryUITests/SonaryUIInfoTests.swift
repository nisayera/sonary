import Testing
@testable import SonaryUI

@Test func packageNameIsStable() {
    #expect(SonaryUIInfo.name == "SonaryUI")
}
