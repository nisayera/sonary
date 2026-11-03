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

struct OutputSwitchingTests {
    private let devices = [
        AudioDevice(id: 1, name: "MacBook Pro Speakers", hasOutput: true, hasInput: false),
        AudioDevice(id: 2, name: "AirPods Pro", hasOutput: true, hasInput: true),
        AudioDevice(id: 3, name: "Studio Display", hasOutput: true, hasInput: false),
    ]

    @Test func cyclesAndWrapsAround() {
        #expect(nextOutputDevice(after: 1, in: devices)?.id == 2)
        #expect(nextOutputDevice(after: 3, in: devices)?.id == 1)
    }

    @Test func unknownCurrentStartsAtTheTop() {
        #expect(nextOutputDevice(after: 99, in: devices)?.id == 1)
        #expect(nextOutputDevice(after: nil, in: devices)?.id == 1)
    }

    @Test func oneDeviceHasNowhereToGo() {
        #expect(nextOutputDevice(after: 1, in: [devices[0]]) == nil)
        #expect(nextOutputDevice(after: nil, in: []) == nil)
    }

    @Test func recognisesHeadphones() {
        #expect(isHeadphoneLike("AirPods Pro"))
        #expect(isHeadphoneLike("Sony WH-1000XM5"))
        #expect(isHeadphoneLike("Externe Kopfhörer"))
        #expect(!isHeadphoneLike("MacBook Pro Speakers"))
        #expect(!isHeadphoneLike("Studio Display"))
    }

    @Test func volumeOnlyEverGoesDown() {
        #expect(volumeAfterUnplug(current: 0.8, limit: 0.25) == 0.25)
        #expect(volumeAfterUnplug(current: 0.1, limit: 0.25) == 0.1)
        #expect(volumeAfterUnplug(current: 2, limit: 5) == 1)
    }
}
