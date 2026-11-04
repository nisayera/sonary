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
