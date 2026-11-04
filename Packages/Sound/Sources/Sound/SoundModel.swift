import AppKit
import CoreAudio
import IOKit.ps
import IOKit.pwr_mgt
import Observation
import SonaryCore

public struct SoundSettings: Codable, Equatable, Sendable {
    public var micMuteShortcut = true
    /// Keep the media keys from launching a music app that is not running.
    public var mediaKeyGuard = false
    public var outputSwitchShortcut = true
    /// Turn the volume down to this when headphones are unplugged; 0 leaves it alone.
    public var volumeAfterUnplug = 0.25
    /// Hold the stronger assertion so the Mac also stays awake with the lid shut.
    public var keepAwakeWithClosedLid = false
    /// The app whose running state can hold keep awake, as a bundle identifier.
    public var keepAwakeApp = ""
    public init() {}
}

private func mediaTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let model = Unmanaged<SoundModel>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { model.reenableMediaTap() }
        return Unmanaged.passUnretained(event)
    }
    // Media keys arrive as system-defined events, with the key packed into the event's data.
    guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
          let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8
    else { return Unmanaged.passUnretained(event) }
    let code = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
    let isDown = ((nsEvent.data1 & 0x0000_FF00) >> 8) == 0x0A
    guard let key = MediaKey(systemDefinedKeyCode: code) else { return Unmanaged.passUnretained(event) }
    let pass = MainActor.assumeIsolated { model.handleMediaKey(key, isDown: isDown) }
    return pass ? Unmanaged.passUnretained(event) : nil
}

public struct RunningApp: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
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
    @ObservationIgnored private var keepAwakeCondition: KeepAwakeCondition?
    @ObservationIgnored private var lastOutputName: String?
    @ObservationIgnored private var mediaTap: CFMachPort?
    @ObservationIgnored private var mediaSource: CFRunLoopSource?
    /// Bundle IDs of the players Sonary will talk to; it never launches one.
    @ObservationIgnored private let players = ["com.apple.Music", "com.spotify.client"]
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
        if settings.mediaKeyGuard { installMediaTap() } else { removeMediaTap() }
    }

    func stop() {
        removeMediaTap()
        refreshTask?.cancel()
        refreshTask = nil
        applyShortcut(running: false)
        setKeepAwake(nil, on: false)
    }

    public func refresh() {
        let all = AudioSystem.allDevices()
        outputs = devices(all, output: true)
        inputs = devices(all, output: false)
        let previousName = lastOutputName
        defaultOutput = AudioSystem.defaultDevice(output: true)
        defaultInput = AudioSystem.defaultDevice(output: false)
        let currentName = outputs.first { $0.id == defaultOutput }?.name
        lastOutputName = currentName
        refreshLevels()
        // Headphones gone and the speakers took over: turn the volume down before it startles anyone.
        if settings.volumeAfterUnplug > 0, let previousName, isHeadphoneLike(previousName),
           let currentName, !isHeadphoneLike(currentName), let volume = outputVolume {
            let wanted = volumeAfterUnplug(current: volume, limit: settings.volumeAfterUnplug)
            if wanted < volume { setOutputVolume(wanted) }
        }
    }

    private func refreshLevels() {
        outputVolume = defaultOutput.flatMap { AudioSystem.volume(of: $0, output: true) }
        if let input = defaultInput {
            micMuted = AudioSystem.isMuted(input, output: false) ?? ((AudioSystem.volume(of: input, output: false) ?? 1) == 0)
        }
    }

    public func selectOutput(_ id: UInt32) { AudioSystem.setDefaultDevice(id, output: true); refresh() }

    /// Moves to the next output device, for the keyboard shortcut.
    public func cycleOutput() {
        guard let next = nextOutputDevice(after: defaultOutput, in: outputs) else { return }
        selectOutput(next.id)
    }
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
        if refreshTask != nil, settings.mediaKeyGuard { installMediaTap() } else { removeMediaTap() }
    }

    // MARK: Media keys

    private func installMediaTap() {
        guard mediaTap == nil else { return }
        let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mediaTap = tap
        mediaSource = source
    }

    private func removeMediaTap() {
        if let mediaTap { CGEvent.tapEnable(tap: mediaTap, enable: false) }
        if let mediaSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), mediaSource, .commonModes) }
        mediaTap = nil
        mediaSource = nil
    }

    /// False swallows the key press, after Sonary has passed the command to a running player.
    func handleMediaKey(_ key: MediaKey, isDown: Bool) -> Bool {
        let running = players.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard shouldHandleMediaKey(playersRunning: running, guardEnabled: settings.mediaKeyGuard) else { return true }
        guard isDown else { return false }
        let player = players.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        let name = player == "com.spotify.client" ? "Spotify" : "Music"
        let command = switch key {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(name)\" to \(command)")?.executeAndReturnError(&error)
        return false
    }

    func reenableMediaTap() {
        if let mediaTap { CGEvent.tapEnable(tap: mediaTap, enable: true) }
    }

    private static let ctrlOpt = KeyModifier.control | KeyModifier.option

    static var shortcutDefinitions: [ShortcutDefinition] { [
        ShortcutDefinition(id: "sound.micMute", title: String(localized: "Mute microphone", bundle: .module),
                           group: String(localized: "Sound", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 46, modifiers: SoundModel.ctrlOpt)),
        ShortcutDefinition(id: "sound.cycleOutput", title: String(localized: "Switch output", bundle: .module),
                           group: String(localized: "Sound", bundle: .module),
                           defaultCombo: KeyCombo(keyCode: 31, modifiers: SoundModel.ctrlOpt)),
    ] }

    private func applyShortcut(running: Bool) {
        let shortcuts = ShortcutStore.shared
        shortcuts.describe(Self.shortcutDefinitions)
        shortcuts.unbindAll(prefix: "sound.")
        guard running else { return }
        if settings.micMuteShortcut {
            shortcuts.bind("sound.micMute") { [weak self] in self?.toggleMicMute() }
        }
        if settings.outputSwitchShortcut {
            shortcuts.bind("sound.cycleOutput") { [weak self] in self?.cycleOutput() }
        }
    }

    // MARK: Keep awake

    public func setKeepAwake(_ duration: KeepAwakeDuration?, on: Bool) {
        guard on, let duration else { return setKeepAwake(nil) }
        setKeepAwake(.duration(duration))
    }

    /// Starts keep awake under a condition, or stops it when the condition is nil.
    public func setKeepAwake(_ condition: KeepAwakeCondition?) {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        keepAwakeActive = false
        keepAwakeEndsAt = nil
        keepAwakeCondition = nil
        guard let condition else { return }
        let reason = "Sonary keeps your Mac awake" as CFString
        let type = keepAwakeAssertionType(closedLid: settings.keepAwakeWithClosedLid) as CFString
        guard IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          reason, &assertion) == kIOReturnSuccess else {
            assertion = 0
            return
        }
        keepAwakeActive = true
        keepAwakeCondition = condition
        switch condition {
        case .duration(let duration):
            guard let seconds = duration.seconds else { return }
            keepAwakeEndsAt = Date().addingTimeInterval(seconds)
            keepAwakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.setKeepAwake(nil)
            }
        case .whileAppRuns, .whilePowered:
            keepAwakeTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    guard let self, let condition = self.keepAwakeCondition else { return }
                    guard keepAwakeShouldContinue(condition: condition,
                                                  runningBundleIDs: Self.runningBundleIDs(),
                                                  onPower: Self.onPower()) else {
                        self.setKeepAwake(nil)
                        return
                    }
                }
            }
        }
    }

    /// Keep awake for as long as the app with this bundle identifier is running.
    public func keepAwakeWhileAppRuns(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        setKeepAwake(.whileAppRuns(bundleID))
    }

    /// Keep awake for as long as the Mac is plugged in.
    public func keepAwakeWhilePowered() { setKeepAwake(.whilePowered) }

    /// The apps the user can pick from, with their bundle identifiers.
    public var runningApps: [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      let name = app.localizedName, seen.insert(id).inserted else { return nil }
                return RunningApp(id: id, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The display name for a bundle identifier, falling back to the identifier itself.
    public func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .compactMap(\.localizedName).first ?? bundleID
    }

    private static func runningBundleIDs() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    private static func onPower() -> Bool {
        guard let value = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return true }
        return (value as String) != kIOPMBatteryPowerKey
    }
}
