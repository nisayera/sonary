import AppKit
import CoreAudio
import IOKit.pwr_mgt
import Observation
import SonaryCore

public struct SoundSettings: Codable, Equatable, Sendable {
    public var micMuteShortcut = true
    public init() {}
}

/// Output and input switching, volume, microphone mute and keep awake.
@MainActor
@Observable
public final class SoundModel {
    public private(set) var outputs: [AudioDevice] = []
    public private(set) var inputs: [AudioDevice] = []
    public private(set) var defaultOutput: UInt32?
    public private(set) var defaultInput: UInt32?
    public private(set) var outputVolume: Double?
    public private(set) var micMuted = false
    public private(set) var keepAwakeEndsAt: Date?
    public private(set) var keepAwakeActive = false
    public private(set) var settings: SoundSettings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var keepAwakeTask: Task<Void, Never>?
    @ObservationIgnored private var micKey: HotKey?
    @ObservationIgnored private var volumeBeforeMute: Double?
    @ObservationIgnored private var listening = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "sound.settings"),
           let settings = try? JSONDecoder().decode(SoundSettings.self, from: data) {
            self.settings = settings
        } else {
            settings = SoundSettings()
        }
    }

    func start() {
        refresh()
        if !listening {
            listening = true
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                             kAudioHardwarePropertyDefaultInputDevice] {
                var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        // Volume can change from the keyboard; check it now and then while the module runs.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refreshLevels()
            }
        }
        applyShortcut(running: true)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        applyShortcut(running: false)
        setKeepAwake(nil, on: false)
    }

    public func refresh() {
        let all = AudioSystem.allDevices()
        outputs = devices(all, output: true)
        inputs = devices(all, output: false)
        defaultOutput = AudioSystem.defaultDevice(output: true)
        defaultInput = AudioSystem.defaultDevice(output: false)
        refreshLevels()
    }

    private func refreshLevels() {
        outputVolume = defaultOutput.flatMap { AudioSystem.volume(of: $0, output: true) }
        if let input = defaultInput {
            micMuted = AudioSystem.isMuted(input, output: false) ?? ((AudioSystem.volume(of: input, output: false) ?? 1) == 0)
        }
    }

    public func selectOutput(_ id: UInt32) { AudioSystem.setDefaultDevice(id, output: true); refresh() }
    public func selectInput(_ id: UInt32) { AudioSystem.setDefaultDevice(id, output: false); refresh() }

    public func setOutputVolume(_ value: Double) {
        guard let output = defaultOutput else { return }
        AudioSystem.setVolume(value, of: output, output: true)
        outputVolume = clampedVolume(value)
    }

    public func toggleMicMute() {
        guard let input = defaultInput else { return }
        let mute = !micMuted
        if !AudioSystem.setMuted(mute, input, output: false) {
            // No mute switch on this microphone: turn its level down and back up instead.
            if mute {
                volumeBeforeMute = AudioSystem.volume(of: input, output: false)
                AudioSystem.setVolume(0, of: input, output: false)
            } else {
                AudioSystem.setVolume(volumeBeforeMute ?? 0.8, of: input, output: false)
            }
        }
        refreshLevels()
    }

    public func update(_ change: (inout SoundSettings) -> Void) {
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "sound.settings") }
        applyShortcut(running: refreshTask != nil)
    }

    private func applyShortcut(running: Bool) {
        micKey?.unregister()
        micKey = nil
        guard running, settings.micMuteShortcut else { return }
        // ⌃⌥M (key code 46).
        micKey = HotKey(keyCode: 46, modifiers: 4096 | 2048) { [weak self] in self?.toggleMicMute() }
    }

    // MARK: Keep awake

    public func setKeepAwake(_ duration: KeepAwakeDuration?, on: Bool) {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        keepAwakeActive = false
        keepAwakeEndsAt = nil
        guard on, let duration else { return }
        let reason = "Sonary keeps your Mac awake" as CFString
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess else {
            assertion = 0
            return
        }
        keepAwakeActive = true
        if let seconds = duration.seconds {
            keepAwakeEndsAt = Date().addingTimeInterval(seconds)
            keepAwakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.setKeepAwake(nil, on: false)
            }
        }
    }
}
