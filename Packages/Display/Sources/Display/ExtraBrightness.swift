import AppKit

/// How much headroom above normal white a display has. 1 means none, so there is
/// nothing extra to give and the setting stays hidden.
public func extraBrightnessHeadroom(maxPotentialEDR: CGFloat) -> Double {
    max(0, Double(maxPotentialEDR) - 1)
}

/// The white value a boost of `amount` (0…1) asks the display for, within what it can
/// actually do. 0 is ordinary white; 1 asks for everything the panel has.
public func extraBrightnessValue(amount: Double, maxPotentialEDR: CGFloat) -> Double {
    let headroom = extraBrightnessHeadroom(maxPotentialEDR: maxPotentialEDR)
    guard headroom > 0 else { return 1 }
    return 1 + min(max(amount, 0), 1) * headroom
}

/// A thin layer of extended-range white over the screen. Asking for white brighter than
/// the display's normal maximum makes it open up its headroom, which is the only way to
/// reach an XDR panel's extra brightness without a private API. The layer is almost
/// transparent, so what is underneath stays readable; clicks go straight through.
@MainActor
final class ExtraBrightnessOverlay {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    /// Applies a boost of 0…1 to one screen, or takes the layer away at 0.
    func apply(amount: Double, to screen: NSScreen, id: CGDirectDisplayID) {
        guard amount > 0, extraBrightnessHeadroom(
            maxPotentialEDR: screen.maximumPotentialExtendedDynamicRangeColorComponentValue) > 0 else {
            remove(id)
            return
        }
        let value = extraBrightnessValue(
            amount: amount, maxPotentialEDR: screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let window = windows[id] ?? makeWindow(for: screen)
        windows[id] = window
        window.setFrame(screen.frame, display: true)
        window.contentView?.layer?.backgroundColor = CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB(),
            components: [CGFloat(value), CGFloat(value), CGFloat(value), 0.02]) ?? .white
        window.orderFrontRegardless()
    }

    func remove(_ id: CGDirectDisplayID) {
        windows.removeValue(forKey: id)?.orderOut(nil)
    }

    func removeAll() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.displaysWhenScreenProfileChanges = true
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.wantsExtendedDynamicRangeContent = true
        window.contentView = view
        return window
    }
}
