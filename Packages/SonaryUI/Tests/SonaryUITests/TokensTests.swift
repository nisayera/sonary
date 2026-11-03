import Testing
import SwiftUI
@testable import SonaryUI

struct TokensTests {
    @Test func spacingValuesAreOnGrid() {
        let values = [Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl]
        #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
        #expect(Spacing.s == 8)
    }

    @Test func motionPolicyReturnsFadeWhenReduceMotion() {
        #expect(sonaryAnimation(true) == .easeInOut(duration: SonaryMotion.fadeDuration))
        #expect(sonaryAnimation(false) == .sonarySpring)
    }

    @Test func springDurationUnder500ms() {
        #expect(SonaryMotion.springDuration < 0.5)
    }
}
