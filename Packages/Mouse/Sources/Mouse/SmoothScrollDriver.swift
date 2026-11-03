import AppKit
import QuartzCore

/// Feeds the `SmoothScroller` to the system once per display frame while there is something left to scroll.
@MainActor
final class SmoothScrollDriver: NSObject {
    private static let pixelsPerLine = 10.0

    private let scroller: Locked<SmoothScroller>
    private var link: CADisplayLink?
    private var carryY = 0.0
    private var carryX = 0.0

    init(scroller: Locked<SmoothScroller>) {
        self.scroller = scroller
        super.init()
    }

    /// Makes sure frames are being delivered.
    func wake() {
        if link == nil {
            guard let screen = NSScreen.main else { return }
            let newLink = screen.displayLink(target: self, selector: #selector(tick(_:)))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
        link?.isPaused = false
    }

    func stop() {
        link?.invalidate()
        link = nil
        carryY = 0
        carryX = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
        let (step, idle) = scroller.withValue { scroller -> ((dy: Double, dx: Double), Bool) in
            let result = scroller.step(dt: dt)
            return (result, scroller.isIdle)
        }
        // Carry the fractional pixels over so the total distance stays exact.
        let wantY = step.dy * Self.pixelsPerLine + carryY
        let wantX = step.dx * Self.pixelsPerLine + carryX
        let pixelsY = wantY.rounded()
        let pixelsX = wantX.rounded()
        carryY = wantY - pixelsY
        carryX = wantX - pixelsX
        if pixelsY != 0 || pixelsX != 0 {
            SyntheticEvents.scroll(pixelsY: Int32(clamping: Int(pixelsY)), pixelsX: Int32(clamping: Int(pixelsX)))
        }
        if idle {
            link.isPaused = true
        }
    }
}
