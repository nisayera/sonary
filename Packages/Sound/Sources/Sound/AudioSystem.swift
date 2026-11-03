import AudioToolbox
import CoreAudio
import Foundation

/// Thin wrapper around the Core Audio HAL: devices, defaults, volume and mute.
enum AudioSystem {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func allDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            AudioDevice(id: id, name: name(of: id) ?? "?", hasOutput: channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0,
                        hasInput: channelCount(id, scope: kAudioDevicePropertyScopeInput) > 0)
        }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID? {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    static func setDefaultDevice(_ id: AudioDeviceID, output: Bool) {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    static func volume(of id: AudioDeviceID, output: Bool) -> Double? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                           output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func setVolume(_ volume: Double, of id: AudioDeviceID, output: Bool) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                           output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput)
        var value = Float32(clampedVolume(volume))
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ id: AudioDeviceID, output: Bool) -> Bool? {
        var addr = address(kAudioDevicePropertyMute, output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    /// Returns false when the device has no mute switch.
    @discardableResult
    static func setMuted(_ muted: Bool, _ id: AudioDeviceID, output: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
