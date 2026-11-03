import Foundation
import Testing
@testable import Sound

struct SoundLogicTests {
    private let all = [
        AudioDevice(id: 1, name: "Studio Display", hasOutput: true, hasInput: true),
        AudioDevice(id: 2, name: "AirPods", hasOutput: true, hasInput: true),
        AudioDevice(id: 3, name: "USB Mic", hasOutput: false, hasInput: true),
    ]

    @Test func outputsSortedByName() {
        #expect(devices(all, output: true).map(\.id) == [2, 1])
    }

    @Test func inputsIncludeMicOnlyDevices() {
        #expect(devices(all, output: false).map(\.id) == [2, 1, 3])
    }

    @Test func volumeIsClamped() {
        #expect(clampedVolume(1.4) == 1)
        #expect(clampedVolume(-0.2) == 0)
        #expect(clampedVolume(0.001) == 0)
        #expect(clampedVolume(0.5) == 0.5)
    }

    @Test func keepAwakeDurations() {
        #expect(KeepAwakeDuration.oneHour.seconds == 3600)
        #expect(KeepAwakeDuration.indefinitely.seconds == nil)
    }

    @Test func remainingNeverNegative() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(keepAwakeRemaining(endsAt: now.addingTimeInterval(-5), now: now) == 0)
        #expect(keepAwakeRemaining(endsAt: now.addingTimeInterval(60), now: now) == 60)
        #expect(keepAwakeRemaining(endsAt: nil, now: now) == nil)
    }
}
