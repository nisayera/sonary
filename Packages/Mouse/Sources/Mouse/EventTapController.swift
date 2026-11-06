import AppKit
import CoreGraphics

public enum MouseError: LocalizedError {
    case tapUnavailable

    public var errorDescription: String? {
        switch self {
        case .tapUnavailable:
            String(localized: "Sonary could not watch mouse events. Allow Sonary under Privacy & Security > Accessibility.", bundle: .module)
        }
    }
}

private func tapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

/// Runs a session event tap on its own thread and applies `EventProcessor` decisions to mouse events.
final class EventTapController: @unchecked Sendable {
    private let processor: Locked<EventProcessor>
    private let scroller: Locked<SmoothScroller>
    private let swallowedUps = Locked<Set<Int>>([])
    private let frontmost = FrontmostApp()
    private let tapBox = Locked<CFMachPort?>(nil)
    private let runLoopBox = Locked<CFRunLoop?>(nil)
    private let driver = Locked<SmoothScrollDriver?>(nil)
    private let middleClickEnabled = Locked<Bool>(false)
    /// Where each button was pressed, so a push can be measured when it comes up.
    private let gestureOrigins = Locked<[Int: CGPoint]>([:])

    init(settings: MouseSettings) {
        middleClickEnabled.withValue { $0 = settings.threeFingerMiddleClick }
        processor = Locked(EventProcessor(settings: settings))
        scroller = Locked(SmoothScroller(smoothness: settings.smoothness))
    }

    @MainActor
    func start() throws {
        let mask: [CGEventType] = [
            .scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        ]
        let eventMask = mask.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: eventMask, callback: tapCallback, userInfo: userInfo
        ) else { throw MouseError.tapUnavailable }
        tapBox.withValue { $0 = tap }
        frontmost.start()
        let smoothDriver = SmoothScrollDriver(scroller: scroller)
        driver.withValue { $0 = smoothDriver }

        let boxed = UncheckedBox(value: tap)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [runLoopBox] in
            let source = CFMachPortCreateRunLoopSource(nil, boxed.value, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: boxed.value, enable: true)
            runLoopBox.withValue { $0 = loop }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "app.sonary.mouse.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    @MainActor
    func stop() {
        if let tap = tapBox.withValue({ $0 }) { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop = runLoopBox.withValue({ $0 }) { CFRunLoopStop(loop) }
        tapBox.withValue { $0 = nil }
        runLoopBox.withValue { $0 = nil }
        driver.withValue { $0 }?.stop()
        driver.withValue { $0 = nil }
        frontmost.stop()
    }

    func update(settings: MouseSettings) {
        middleClickEnabled.withValue { $0 = settings.threeFingerMiddleClick }
        processor.withValue { $0.update(settings: settings) }
        scroller.withValue { $0 = SmoothScroller(smoothness: settings.smoothness) }
    }

    // MARK: - Tap callback (runs on the tap thread)

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = tapBox.withValue({ $0 }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            return handleScroll(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if type == .leftMouseDown, isThreeFingerPress(event) {
                let point = event.location
                swallowedUps.withValue { _ = $0.insert(0) }
                DispatchQueue.main.async { SyntheticEvents.middleClick(at: point) }
                return nil
            }
            return handleDown(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if let origin = gestureOrigins.withValue({ $0.removeValue(forKey: button) }) {
                let direction = gestureDirection(from: origin, to: event.location)
                let decision = processor.withValue {
                    $0.process(.buttonUp(button: button, direction: direction), bundleID: frontmost.bundleID)
                }
                swallowedUps.withValue { _ = $0.remove(button) }
                if case let .perform(action) = decision {
                    DispatchQueue.main.async { SyntheticEvents.perform(action) }
                }
                if case .passThrough = decision { return Unmanaged.passUnretained(event) }
                return nil
            }
            let swallow = swallowedUps.withValue { $0.remove(button) != nil }
            return swallow ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let sample = ScrollSample(
            deltaY: event.getDoubleValueField(.scrollWheelEventDeltaAxis1),
            deltaX: event.getDoubleValueField(.scrollWheelEventDeltaAxis2),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
            momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
            modifiers: modifierSet(from: event.flags)
        )
        let bundleID = frontmost.bundleID
        let decision = processor.withValue { $0.process(.scroll(sample), bundleID: bundleID) }
        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case let .replaceScroll(result):
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(result.deltaY))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(result.deltaX))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(result.deltaY * 10))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(result.deltaX * 10))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: result.deltaY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: result.deltaX)
            return Unmanaged.passUnretained(event)
        case let .injectSmooth(result):
            scroller.withValue { $0.add(deltaY: result.deltaY, deltaX: result.deltaX) }
            let driver = driver
            Task { @MainActor in driver.withValue { $0 }?.wake() }
            return nil
        case let .perform(action):
            // A sideways wheel with an action, or the wheel zooming: the scroll is
            // replaced by the action, run once the tap has answered.
            DispatchQueue.main.async { SyntheticEvents.perform(action) }
            return nil
        case .swallow:
            return nil
        }
    }

    private func modifierSet(from flags: CGEventFlags) -> ScrollModifierSet {
        var set = ScrollModifierSet()
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        return set
    }

    /// A trackpad click carries its touches with it, so the fingers that were down
    /// when it landed can be counted. A mouse carries none and is never converted.
    private func isThreeFingerPress(_ event: CGEvent) -> Bool {
        guard middleClickEnabled.withValue({ $0 }), let nsEvent = NSEvent(cgEvent: event) else { return false }
        let touches = nsEvent.touches(matching: .touching, in: nil).count
        return shouldBecomeMiddleClick(touchCount: touches, enabled: true)
    }

    private func handleDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let bundleID = frontmost.bundleID
        if button > 2 {
            let mappings = processor.withValue { $0.gestureMappings(for: bundleID) }
            if hasGestures(button: button, in: mappings) {
                gestureOrigins.withValue { $0[button] = event.location }
            }
        }
        let decision = processor.withValue {
            $0.process(.buttonDown(button: button, timestampNanoseconds: event.timestamp), bundleID: bundleID)
        }
        switch decision {
        case .passThrough, .replaceScroll, .injectSmooth:
            return Unmanaged.passUnretained(event)
        case .swallow:
            swallowedUps.withValue { _ = $0.insert(button) }
            return nil
        case let .perform(action):
            swallowedUps.withValue { _ = $0.insert(button) }
            DispatchQueue.main.async { SyntheticEvents.perform(action) }
            return nil
        }
    }
}
