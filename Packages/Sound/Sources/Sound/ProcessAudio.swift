import CoreAudio
import Foundation

/// An app Core Audio knows about, and whether it is making a sound right now.
public struct AudioProcess: Equatable, Sendable, Identifiable {
    public var objectID: UInt32
    public var pid: pid_t
    public var bundleID: String
    public var isPlaying: Bool
    public var id: UInt32 { objectID }

    public init(objectID: UInt32, pid: pid_t, bundleID: String, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = isPlaying
    }
}

/// The apps worth showing in a mixer: the ones actually playing, Sonary left out, each
/// app once, in a steady order so the list does not jump about while you look at it.
public func mixerEntries(_ processes: [AudioProcess], ownBundleID: String?) -> [AudioProcess] {
    var seen = Set<String>()
    return processes
        .filter { $0.isPlaying && !$0.bundleID.isEmpty && $0.bundleID != ownBundleID }
        .filter { seen.insert($0.bundleID).inserted }
        .sorted { $0.bundleID < $1.bundleID }
}

/// Reads which apps are playing audio. This only asks Core Audio questions; it never
/// changes a device, so it cannot disturb what the user is listening to.
enum ProcessAudioReader {
    /// Core Audio's list of process objects. Empty on a system that does not offer it.
    static func processes() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { process(ids: $0) }
    }

    private static func process(ids objectID: AudioObjectID) -> AudioProcess? {
        guard let pid: pid_t = value(objectID, kAudioProcessPropertyPID) else { return nil }
        let bundleID: String = string(objectID, kAudioProcessPropertyBundleID) ?? ""
        let playing: UInt32 = value(objectID, kAudioProcessPropertyIsRunningOutput) ?? 0
        return AudioProcess(objectID: objectID, pid: pid, bundleID: bundleID, isPlaying: playing != 0)
    }

    private static func value<T>(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func string(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: CFString?
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &result) == noErr,
              let result else { return nil }
        return result as String
    }
}
