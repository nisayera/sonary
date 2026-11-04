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

struct MediaKeyTests {
    @Test func recognisesTheThreeKeys() {
        #expect(MediaKey(systemDefinedKeyCode: 16) == .playPause)
        #expect(MediaKey(systemDefinedKeyCode: 17) == .next)
        #expect(MediaKey(systemDefinedKeyCode: 18) == .previous)
        #expect(MediaKey(systemDefinedKeyCode: 7) == nil)
    }

    @Test func stepsInOnlyWhenAPlayerIsRunning() {
        #expect(shouldHandleMediaKey(playersRunning: true, guardEnabled: true))
        #expect(!shouldHandleMediaKey(playersRunning: false, guardEnabled: true))
        #expect(!shouldHandleMediaKey(playersRunning: true, guardEnabled: false))
    }
}

@Suite struct KeepAwakeConditionTests {
    @Test func closedLidNeedsTheStrongerAssertion() {
        #expect(keepAwakeAssertionType(closedLid: true) != keepAwakeAssertionType(closedLid: false))
        #expect(keepAwakeAssertionType(closedLid: false).contains("Display"))
    }

    @Test func durationAlwaysContinues() {
        #expect(keepAwakeShouldContinue(condition: .duration(.oneHour), runningBundleIDs: [], onPower: false))
    }

    @Test func appConditionFollowsTheApp() {
        let running = ["com.apple.Music"]
        #expect(keepAwakeShouldContinue(condition: .whileAppRuns("com.apple.Music"),
                                        runningBundleIDs: running, onPower: false))
        #expect(keepAwakeShouldContinue(condition: .whileAppRuns("COM.APPLE.MUSIC"),
                                        runningBundleIDs: running, onPower: false))
        #expect(!keepAwakeShouldContinue(condition: .whileAppRuns("com.spotify.client"),
                                         runningBundleIDs: running, onPower: false))
    }

    @Test func powerConditionFollowsThePlug() {
        #expect(keepAwakeShouldContinue(condition: .whilePowered, runningBundleIDs: [], onPower: true))
        #expect(!keepAwakeShouldContinue(condition: .whilePowered, runningBundleIDs: [], onPower: false))
    }
}

@Suite struct InputLevelTests {
    @Test func silenceSitsAtTheBottom() {
        #expect(inputBar(rms: 0) == 0)
        #expect(inputBar(rms: -1) == 0, "a nonsense reading is not a loud one")
    }

    @Test func fullScaleIsTheTop() {
        #expect(inputBar(rms: 1) == 1)
        #expect(inputBar(rms: 4) == 1, "anything above the scale is clamped")
    }

    @Test func halfwayDownTheScaleIsHalfTheBar() {
        // -30 dB on a 60 dB scale is the middle.
        let half = inputBar(rms: Float(pow(10.0, -30.0 / 20.0)))
        #expect(abs(half - 0.5) < 0.01)
    }

    @Test func rootMeanSquareOfKnownSamples() {
        #expect(rootMeanSquare([]) == 0)
        #expect(rootMeanSquare([0, 0, 0]) == 0)
        #expect(abs(rootMeanSquare([1, -1, 1, -1]) - 1) < 0.0001)
        #expect(abs(rootMeanSquare([0.5, -0.5]) - 0.5) < 0.0001)
    }

    @Test func theDisplayConditionFollowsTheDisplays() {
        #expect(keepAwakeShouldContinue(condition: .whileDisplayConnected, runningBundleIDs: [],
                                        onPower: false, externalDisplays: 1))
        #expect(!keepAwakeShouldContinue(condition: .whileDisplayConnected, runningBundleIDs: [],
                                         onPower: true, externalDisplays: 0))
    }
}
