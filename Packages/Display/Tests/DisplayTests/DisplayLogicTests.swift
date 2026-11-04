import Foundation
import Testing
@testable import Display

@Suite struct BluetoothSleepTests {
    @Test func onlyRestoresWhatSonaryTurnedOff() {
        #expect(shouldRestoreBluetooth(turnedOffBySonary: true, settingEnabled: true))
        #expect(!shouldRestoreBluetooth(turnedOffBySonary: false, settingEnabled: true))
        #expect(!shouldRestoreBluetooth(turnedOffBySonary: true, settingEnabled: false))
    }
}
