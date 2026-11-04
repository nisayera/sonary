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

@Suite struct ExtraBrightnessTests {
    @Test func aPanelWithoutHeadroomHasNothingToGive() {
        #expect(extraBrightnessHeadroom(maxPotentialEDR: 1) == 0)
        #expect(extraBrightnessHeadroom(maxPotentialEDR: 0.5) == 0)
        #expect(extraBrightnessValue(amount: 1, maxPotentialEDR: 1) == 1, "ordinary white, nothing more")
    }

    @Test func asksForWhiteWithinWhatThePanelCanDo() {
        #expect(abs(extraBrightnessHeadroom(maxPotentialEDR: 1.6) - 0.6) < 0.0001)
        #expect(abs(extraBrightnessValue(amount: 0, maxPotentialEDR: 1.6) - 1) < 0.0001)
        #expect(abs(extraBrightnessValue(amount: 0.5, maxPotentialEDR: 1.6) - 1.3) < 0.0001)
        #expect(abs(extraBrightnessValue(amount: 1, maxPotentialEDR: 1.6) - 1.6) < 0.0001)
    }

    @Test func asksForNoMoreThanTheMaximumHoweverItIsCalled() {
        #expect(abs(extraBrightnessValue(amount: 5, maxPotentialEDR: 1.6) - 1.6) < 0.0001)
        #expect(abs(extraBrightnessValue(amount: -2, maxPotentialEDR: 1.6) - 1) < 0.0001)
    }
}
