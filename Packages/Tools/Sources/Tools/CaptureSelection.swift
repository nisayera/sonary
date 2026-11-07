import CoreGraphics
import Foundation

/// The rectangle between two corners, however the drag went. Always has a positive size.
public func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
           width: abs(end.x - start.x), height: abs(end.y - start.y))
}

/// Keeps a selection inside the screen it was drawn on.
public func clampSelection(_ rect: CGRect, to bounds: CGRect) -> CGRect {
    rect.intersection(bounds)
}

/// A drag too small to mean anything, which should capture nothing rather than a
/// few stray pixels.
public func isSelectionUsable(_ rect: CGRect, minimum: CGFloat = 4) -> Bool {
    rect.width >= minimum && rect.height >= minimum
}

/// The size shown next to the pointer while dragging.
public func selectionSizeLabel(_ rect: CGRect) -> String {
    "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
}

/// The patch of screen the magnifier shows: a small square around the pointer, pulled
/// back inside the screen when the pointer is near an edge so the loupe never shows
/// nothing.
public func magnifierSource(at point: CGPoint, in bounds: CGRect, side: CGFloat = 24) -> CGRect {
    let clamped = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    var rect = clamped
    if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
    if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
    if rect.maxX > bounds.maxX { rect.origin.x = bounds.maxX - side }
    if rect.maxY > bounds.maxY { rect.origin.y = bounds.maxY - side }
    return rect.intersection(bounds)
}

/// Where the loupe sits so it does not cover the pointer or run off the screen.
public func magnifierPlacement(at point: CGPoint, in bounds: CGRect,
                               size: CGFloat = 120, gap: CGFloat = 16) -> CGPoint {
    var x = point.x + gap
    var y = point.y + gap
    if x + size > bounds.maxX { x = point.x - gap - size }
    if y + size > bounds.maxY { y = point.y - gap - size }
    return CGPoint(x: max(bounds.minX, x), y: max(bounds.minY, y))
}

/// What the user wants done with the region they picked.
public enum CapturePurpose: String, CaseIterable, Codable, Sendable {
    case clipboard, file, text, pin
}

/// What the selector does with the region: switched inside it with 1 to 4.
public enum CaptureMode: Int, CaseIterable, Sendable {
    case screenshot = 1, text, color, recording

    /// The mode a digit key picks, by its key code (1, 2, 3, 4 above the letters).
    public init?(keyCode: UInt16) {
        switch keyCode {
        case 18: self = .screenshot
        case 19: self = .text
        case 20: self = .color
        case 21: self = .recording
        default: return nil
        }
    }
}

/// What came out of the selector: the region in screen coordinates, what to do with it,
/// and for the colour mode the colour under the pointer when it could be read.
public struct CaptureChoice: Equatable, Sendable {
    public var rect: CGRect
    public var mode: CaptureMode
    public var color: SampledColor?

    public init(rect: CGRect, mode: CaptureMode, color: SampledColor? = nil) {
        self.rect = rect
        self.mode = mode
        self.color = color
    }
}

public struct SampledColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// What a click or a drag in the selector means. A drag picks its rectangle; a click
/// without one takes the whole screen it landed on, except in the colour mode, where it
/// picks the point. Nil for a drag too small to mean anything.
public func captureRegion(start: CGPoint, end: CGPoint, screen: CGRect, mode: CaptureMode,
                          clickDistance: CGFloat = 3) -> CGRect? {
    let isClick = abs(end.x - start.x) <= clickDistance && abs(end.y - start.y) <= clickDistance
    if mode == .color { return CGRect(x: end.x.rounded(.down), y: end.y.rounded(.down), width: 1, height: 1) }
    if isClick { return screen }
    let rect = clampSelection(selectionRect(from: start, to: end), to: screen)
    return isSelectionUsable(rect) ? rect : nil
}
