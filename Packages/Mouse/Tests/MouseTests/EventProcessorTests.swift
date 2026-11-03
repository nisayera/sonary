import Testing
@testable import Mouse

struct EventProcessorTests {
    private let ms: UInt64 = 1_000_000

    private func processor(_ configure: (inout MouseSettings) -> Void) -> EventProcessor {
        var settings = MouseSettings()
        configure(&settings)
        return EventProcessor(settings: settings)
    }

    @Test func trackpadScrollPassesThrough() {
        var p = processor { $0.linearScroll = true; $0.reverseScroll = true }
        let trackpad = ScrollSample(deltaY: 4, isContinuous: true, scrollPhase: 2)
        let decision = p.process(.scroll(trackpad), bundleID: nil)
        #expect(decision == .passThrough)
    }

    @Test func wheelIsLinearized() {
        var p = processor { $0.linearScroll = true }
        let decision = p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: nil)
        #expect(decision == .replaceScroll(ScrollSample(deltaY: 3)))
    }

    @Test func wheelIsReversed() {
        var p = processor { $0.reverseScroll = true }
        let decision = p.process(.scroll(ScrollSample(deltaY: 2)), bundleID: nil)
        #expect(decision == .replaceScroll(ScrollSample(deltaY: -2)))
    }

    @Test func reverseThenLinearKeepsSizeAndFlipsSign() {
        var p = processor { $0.linearScroll = true; $0.reverseScroll = true }
        let decision = p.process(.scroll(ScrollSample(deltaY: 9)), bundleID: nil)
        #expect(decision == .replaceScroll(ScrollSample(deltaY: -3)))
    }

    @Test func plainWheelWithNoFeaturesPassesThrough() {
        var p = processor { _ in }
        let decision = p.process(.scroll(ScrollSample(deltaY: 2)), bundleID: nil)
        #expect(decision == .passThrough)
    }

    @Test func smoothScrollSwallowsAndInjects() {
        var p = processor { $0.smoothScroll = true; $0.linearScroll = true }
        let decision = p.process(.scroll(ScrollSample(deltaY: 1)), bundleID: nil)
        #expect(decision == .injectSmooth(ScrollSample(deltaY: 3)))
    }

    @Test func disabledAppPassesEverythingThrough() {
        var p = processor {
            $0.linearScroll = true
            $0.appOverrides = ["com.example.off": AppOverride(disabled: true)]
        }
        let decision = p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: "com.example.off")
        #expect(decision == .passThrough)
    }

    @Test func nilBundlePassesWithGlobalSettings() {
        var p = processor { $0.linearScroll = true }
        let decision = p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: nil)
        #expect(decision == .replaceScroll(ScrollSample(deltaY: 3)))
    }

    @Test func mappedButtonPerformsAction() {
        var p = processor { $0.buttonMappings = [ButtonMapping(button: 3, action: .back)] }
        let decision = p.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil)
        #expect(decision == .perform(.back))
    }

    @Test func unmappedButtonPassesThrough() {
        var p = processor { _ in }
        let decision = p.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil)
        #expect(decision == .passThrough)
    }

    @Test func fastSecondClickIsSwallowed() {
        var p = processor { $0.clickFilterMilliseconds = 50 }
        let decision = p.process(.buttonDown(button: 0, timestampNanoseconds: 0), bundleID: nil)
        #expect(decision == .passThrough)
        let decision2 = p.process(.buttonDown(button: 0, timestampNanoseconds: 20 * ms), bundleID: nil)
        #expect(decision2 == .swallow)
    }
}
