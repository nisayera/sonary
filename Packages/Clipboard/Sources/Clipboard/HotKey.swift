import Carbon.HIToolbox

/// A system-wide keyboard shortcut through Carbon's hot key API (no permission needed).
@MainActor
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    private var reference: EventHotKeyRef?
    private let id: UInt32

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x534F4E59), id: id)  // "SONY"
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return nil }
        reference = ref
        Self.actions[id] = action
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKey.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
