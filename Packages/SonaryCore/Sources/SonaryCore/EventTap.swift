import ApplicationServices
import CoreGraphics

/// What a handler wants done with an event that reached its tap.
public enum EventTapVerdict: Equatable, Sendable {
    /// The event goes on to the next tap and the app in front.
    case pass
    /// The event stops here.
    case swallow
}

/// One Quartz event tap on the main run loop, with the parts every tap in Sonary repeated:
/// creating the port, adding and removing its run loop source, asking for Accessibility when
/// the tap cannot be created, and switching the tap back on when macOS turns it off after a
/// slow callback or user input.
///
/// The handler is called on the main thread (the tap's run loop source is on the main run
/// loop), outside any actor, so it can read the event and then step onto the main actor with
/// `MainActor.assumeIsolated` for the plain values it needs, as the hand-written taps did.
@MainActor
public final class EventTap {
    public typealias Handler = @Sendable (CGEventType, CGEvent) -> EventTapVerdict

    private let mask: CGEventMask
    private let place: CGEventTapPlacement
    private let options: CGEventTapOptions
    nonisolated let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Called after macOS had switched the tap off and it was switched on again, for state
    /// that may have missed events in between.
    public var onReenable: () -> Void = {}

    public var isRunning: Bool { port != nil }

    public init(mask: CGEventMask, place: CGEventTapPlacement = .headInsertEventTap,
                options: CGEventTapOptions = .defaultTap, handler: @escaping Handler) {
        self.mask = mask
        self.place = place
        self.options = options
        self.handler = handler
    }

    /// The mask for a list of event types.
    public nonisolated static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }

    /// False when the tap could not be created, which means Accessibility is missing.
    @discardableResult
    public func start(promptForAccessibility: Bool = true) -> Bool {
        guard port == nil else { return true }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: options,
                                           eventsOfInterest: mask, callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            if promptForAccessibility {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    public func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        onReenable()
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    return tap.handler(type, event) == .pass ? Unmanaged.passUnretained(event) : nil
}
