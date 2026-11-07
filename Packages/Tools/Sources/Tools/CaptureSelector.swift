import AppKit
import ScreenCaptureKit
import SwiftUI

/// Sonary's own region selector: one dimmed overlay per screen, a magnifier at the
/// pointer and a live size readout. Escape cancels; a usable drag hands back the
/// region in screen coordinates.
@MainActor
final class CaptureSelectorController {
    private var panels: [NSPanel] = []
    private var views: [SelectionView] = []
    private var finish: ((CaptureChoice?) -> Void)?
    /// What the region will be used for; 1 to 4 switch it while the selector is open.
    private var mode: CaptureMode = .screenshot {
        didSet { for view in views { view.mode = mode } }
    }
    /// Whether the mode bar is shown. Off for captures that only make sense one way,
    /// such as a scrolling screenshot.
    private var switchable = true

    /// Picks a region, for one purpose only.
    func show(completion: @escaping (CGRect?) -> Void) {
        show(mode: .screenshot, switchable: false) { completion($0?.rect) }
    }

    /// Freezes a picture of each screen first, so the magnifier can zoom into it
    /// without capturing again on every pointer move.
    func show(mode: CaptureMode, switchable: Bool = true, completion: @escaping (CaptureChoice?) -> Void) {
        close()
        finish = completion
        self.switchable = switchable
        self.mode = mode
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
            view.mode = mode
            view.showsModes = switchable
            view.onMode = { [weak self] mode in self?.mode = mode }
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                view.backdrop = shots[CGDirectDisplayID(number.uint32Value)]
            }
            view.onFinish = { [weak self] choice in self?.report(choice) }
            panel.contentView = view
            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            panels.append(panel)
            views.append(view)
        }
        NSCursor.crosshair.push()
    }

    private func report(_ choice: CaptureChoice?) {
        let finish = self.finish
        self.finish = nil
        close()
        finish?(choice)
    }

    func close() {
        guard !panels.isEmpty else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = []
        views = []
        NSCursor.pop()
    }
}

/// Draws the dimming, the hole the user is cutting out of it, the size readout and the
/// magnifier. Coordinates are the panel's; `screenOrigin` turns them back into screen ones.
private final class SelectionView: NSView {
    var onFinish: ((CaptureChoice?) -> Void)?
    var onMode: ((CaptureMode) -> Void)?
    var screenOrigin: CGPoint = .zero
    var mode: CaptureMode = .screenshot { didSet { needsDisplay = true } }
    var showsModes = true
    /// Where each mode's label was drawn, so a click on it switches.
    private var modeLabels: [CaptureMode: CGRect] = [:]

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
        let point = convert(event.locationInWindow, from: nil)
        if showsModes, let hit = modeLabels.first(where: { $0.value.contains(point) })?.key {
            onMode?(hit)
            return
        }
        start = point
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
        guard let start, let current else { return }
        guard let rect = captureRegion(start: start, end: current, screen: bounds, mode: mode) else {
            onFinish?(nil)
            return
        }
        let color = mode == .color ? sampledColor(at: current) : nil
        onFinish?(CaptureChoice(rect: CGRect(x: rect.minX + screenOrigin.x, y: rect.minY + screenOrigin.y,
                                             width: rect.width, height: rect.height),
                                mode: mode, color: color))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else if showsModes, let picked = CaptureMode(keyCode: event.keyCode) {
            onMode?(picked)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The colour of the frozen screen picture under a point. Nil without the Screen
    /// Recording permission, when there is no picture to read.
    private func sampledColor(at point: CGPoint) -> SampledColor? {
        guard let backdrop else { return nil }
        let scale = CGFloat(backdrop.width) / max(bounds.width, 1)
        let pixel = CGRect(x: (point.x * scale).rounded(.down), y: ((bounds.height - point.y) * scale).rounded(.down),
                           width: 1, height: 1)
        guard let patch = backdrop.cropping(to: pixel) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return SampledColor(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
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
        if showsModes { drawModeBar() }
    }

    /// The four modes along the top, the current one marked, with a hint for the click.
    private func drawModeBar() {
        let names: [(CaptureMode, String)] = [
            (.screenshot, String(localized: "Screenshot", bundle: .module)),
            (.text, String(localized: "Text", bundle: .module)),
            (.color, String(localized: "Colour", bundle: .module)),
            (.recording, String(localized: "Recording", bundle: .module)),
        ]
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let labels = names.map { mode, name in
            NSAttributedString(string: "\(mode.rawValue)  \(name)",
                               attributes: [.font: font, .foregroundColor: NSColor.white])
        }
        let hint = NSAttributedString(
            string: mode == .color ? String(localized: "Click a point", bundle: .module)
                : String(localized: "Drag an area, or click for the whole screen", bundle: .module),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.75)])
        let padding: CGFloat = 10
        let widths = labels.map { $0.size().width + padding * 2 }
        let total = widths.reduce(0, +) + hint.size().width + padding * 2
        let height: CGFloat = 28
        var x = bounds.midX - total / 2
        let y = bounds.maxY - height - 40
        let bar = CGRect(x: x - 4, y: y - 4, width: total + 8, height: height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
        modeLabels = [:]
        for (index, label) in labels.enumerated() {
            let box = CGRect(x: x, y: y, width: widths[index], height: height)
            let entry = names[index].0
            if entry == mode {
                NSColor.systemPink.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
            }
            label.draw(at: CGPoint(x: box.minX + padding, y: box.midY - label.size().height / 2))
            modeLabels[entry] = box
            x += widths[index]
        }
        hint.draw(at: CGPoint(x: x + padding, y: y + height / 2 - hint.size().height / 2))
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
