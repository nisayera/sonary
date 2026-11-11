import CoreGraphics
import Foundation
import Testing
@testable import SonaryCore

@Suite struct AppleScriptRunnerTests {
    @Test func wrapsTheScriptInATimeout() {
        let script = AppleScriptRunner.wrapped("tell application \"Music\" to playpause", timeout: 3)
        #expect(script == "with timeout of 3 seconds\ntell application \"Music\" to playpause\nend timeout")
        #expect(AppleScriptRunner.wrapped("beep", timeout: 0).hasPrefix("with timeout of 1 seconds\n"))
    }

    @Test func returnsTheResultOfAScript() async {
        // Plain AppleScript without Apple events, so it needs no Automation permission.
        let outcome = await AppleScriptRunner.run("return \"sonary\"")
        #expect(outcome == .success("sonary"))
        #expect(outcome.text == "sonary")
    }

    @Test func reportsAFailingScript() async {
        let outcome = await AppleScriptRunner.run("error \"nope\"")
        #expect(outcome == .failed("nope"))
        #expect(!outcome.succeeded)
    }
}

@Suite struct EventTapTests {
    @Test func maskHasOneBitPerEventType() {
        #expect(EventTap.mask([]) == 0)
        #expect(EventTap.mask([.keyDown]) == CGEventMask(1) << 10)
        #expect(EventTap.mask([.keyDown, .keyUp, .flagsChanged]) == (1 << 10) | (1 << 11) | (1 << 12))
    }
}
