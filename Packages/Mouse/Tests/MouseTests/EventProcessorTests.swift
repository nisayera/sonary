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
        #expect(p.process(.scroll(trackpad), bundleID: nil) == .passThrough)
    }

    @Test func wheelIsLinearized() {
        var p = processor { $0.linearScroll = true }
        #expect(p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: nil) == .replaceScroll(ScrollSample(deltaY: 3)))
    }

    @Test func wheelIsReversed() {
        var p = processor { $0.reverseScroll = true }
        #expect(p.process(.scroll(ScrollSample(deltaY: 2)), bundleID: nil) == .replaceScroll(ScrollSample(deltaY: -2)))
    }

    @Test func reverseThenLinearKeepsSizeAndFlipsSign() {
        var p = processor { $0.linearScroll = true; $0.reverseScroll = true }
        #expect(p.process(.scroll(ScrollSample(deltaY: 9)), bundleID: nil) == .replaceScroll(ScrollSample(deltaY: -3)))
    }

    @Test func plainWheelWithNoFeaturesPassesThrough() {
        var p = processor { _ in }
        #expect(p.process(.scroll(ScrollSample(deltaY: 2)), bundleID: nil) == .passThrough)
    }

    @Test func smoothScrollSwallowsAndInjects() {
        var p = processor { $0.smoothScroll = true; $0.linearScroll = true }
        #expect(p.process(.scroll(ScrollSample(deltaY: 1)), bundleID: nil) == .injectSmooth(ScrollSample(deltaY: 3)))
    }

    @Test func disabledAppPassesEverythingThrough() {
        var p = processor {
            $0.linearScroll = true
            $0.appOverrides = ["com.example.off": AppOverride(disabled: true)]
        }
        #expect(p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: "com.example.off") == .passThrough)
    }

    @Test func nilBundlePassesWithGlobalSettings() {
        var p = processor { $0.linearScroll = true }
        #expect(p.process(.scroll(ScrollSample(deltaY: 7)), bundleID: nil) == .replaceScroll(ScrollSample(deltaY: 3)))
    }

    @Test func mappedButtonPerformsAction() {
        var p = processor { $0.buttonMappings = [ButtonMapping(button: 3, action: .back)] }
        #expect(p.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil) == .perform(.back))
    }

    @Test func unmappedButtonPassesThrough() {
        var p = processor { _ in }
        #expect(p.process(.buttonDown(button: 3, timestampNanoseconds: 0), bundleID: nil) == .passThrough)
    }

    @Test func fastSecondClickIsSwallowed() {
        var p = processor { $0.clickFilterMilliseconds = 50 }
        #expect(p.process(.buttonDown(button: 0, timestampNanoseconds: 0), bundleID: nil) == .passThrough)
        #expect(p.process(.buttonDown(button: 0, timestampNanoseconds: 20 * ms), bundleID: nil) == .swallow)
    }
}
