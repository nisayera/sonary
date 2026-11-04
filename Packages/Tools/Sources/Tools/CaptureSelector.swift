import AppKit
import ScreenCaptureKit
import SwiftUI

/// Sonary's own region selector: one dimmed overlay per screen, a magnifier at the
/// pointer and a live size readout. Escape cancels; a usable drag hands back the
/// region in screen coordinates.
@MainActor
final class CaptureSelectorController {
    private var panels: [NSPanel] = []
    private var finish: ((CGRect?) -> Void)?

    /// Freezes a picture of each screen first, so the magnifier can zoom into it
    /// without capturing again on every pointer move.
    func show(completion: @escaping (CGRect?) -> Void) {
        close()
        finish = completion
        let screens = NSScreen.screens
        Task {
            var shots: [CGDirectDisplayID: CGImage] = [:]
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
                for display in content.displays {
                    let configuration = SCStreamConfiguration()
                    configuration.width = display.width
                    configuration.height = display.height
                    configuration.showsCursor = false
                    if let shot = try? await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(display: display, excludingWindows: []),
                        configuration: configuration) {
                        shots[display.displayID] = shot
                    }
                }
            }
            present(screens: screens, shots: shots)
        }
    }

    private func present(screens: [NSScreen], shots: [CGDirectDisplayID: CGImage]) {
        guard finish != nil else { return }
        for screen in screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenOrigin = screen.frame.origin
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                view.backdrop = shots[CGDirectDisplayID(number.uint32Value)]
            }
            view.onFinish = { [weak self] rect in self?.report(rect) }
            panel.contentView = view
            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            panels.append(panel)
        }
        NSCursor.crosshair.push()
    }

    private func report(_ rect: CGRect?) {
        let finish = self.finish
        self.finish = nil
        close()
        finish?(rect)
    }

    func close() {
        guard !panels.isEmpty else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.pop()
    }
}

/// Draws the dimming, the hole the user is cutting out of it, the size readout and the
/// magnifier. Coordinates are the panel's; `screenOrigin` turns them back into screen ones.
private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    var screenOrigin: CGPoint = .zero

    private var start: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint = .zero
    private var magnifierImage: CGImage?
    /// The frozen picture of this screen, in pixels; the loupe crops from it.
    var backdrop: CGImage?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        pointer = current ?? pointer
        refreshMagnifier()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        refreshMagnifier()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            start = nil
            current = nil
        }
        guard let start, let current else {
            onFinish?(nil)
            return
        }
        let rect = clampSelection(selectionRect(from: start, to: current), to: bounds)
        guard isSelectionUsable(rect) else {
            onFinish?(nil)
            return
        }
        onFinish?(CGRect(x: rect.minX + screenOrigin.x, y: rect.minY + screenOrigin.y,
                         width: rect.width, height: rect.height))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    /// Crops the loupe's patch out of the frozen screen picture. Without the Screen
    /// Recording permission there is no picture, and the loupe shows its crosshair alone.
    private func refreshMagnifier() {
        guard let backdrop else { return }
        let source = magnifierSource(at: pointer, in: bounds)
        guard source.width > 1, source.height > 1 else { return }
        let scale = CGFloat(backdrop.width) / max(bounds.width, 1)
        // The picture's origin is top-left, the view's is bottom-left.
        let pixels = CGRect(x: source.minX * scale,
                            y: (bounds.height - source.maxY) * scale,
                            width: source.width * scale, height: source.height * scale)
        magnifierImage = backdrop.cropping(to: pixels.integral)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let start, let current {
            let rect = clampSelection(selectionRect(from: start, to: current), to: bounds)
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
            drawLabel(selectionSizeLabel(rect), near: rect)
        }
        drawMagnifier()
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let box = CGRect(x: rect.midX - size.width / 2 - 5,
                         y: max(bounds.minY + 2, rect.minY - size.height - 8),
                         width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        string.draw(at: NSPoint(x: box.minX + 5, y: box.minY + 2))
    }

    private func drawMagnifier() {
        let side: CGFloat = 120
        let origin = magnifierPlacement(at: pointer, in: bounds, size: side)
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let clip = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if let magnifierImage, let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .none
            context.draw(magnifierImage, in: box)
        } else {
            NSColor.black.withAlphaComponent(0.6).setFill()
            box.fill()
        }
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: box.minX, y: box.midY))
        cross.line(to: NSPoint(x: box.maxX, y: box.midY))
        cross.move(to: NSPoint(x: box.midX, y: box.minY))
        cross.line(to: NSPoint(x: box.midX, y: box.maxY))
        cross.lineWidth = 1
        cross.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        clip.lineWidth = 1
        clip.stroke()
    }
}
