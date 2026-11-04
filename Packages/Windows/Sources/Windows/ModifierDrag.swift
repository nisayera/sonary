import CoreGraphics

/// What a modifier-drag does: move the window under the pointer, or resize it.
public enum ModifierDragMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, move, resize, moveAndResize

    public var id: String { rawValue }

    public var movesOnLeft: Bool { self == .move || self == .moveAndResize }
    public var resizesOnRight: Bool { self == .resize || self == .moveAndResize }
}

/// A window moved by the pointer: the frame it started from plus how far the pointer
/// has travelled since.
public func draggedFrame(start: CGRect, from origin: CGPoint, to point: CGPoint) -> CGRect {
    CGRect(x: start.minX + (point.x - origin.x), y: start.minY + (point.y - origin.y),
           width: start.width, height: start.height)
}

/// A window resized by the pointer, never smaller than something you can grab again.
public func resizedFrame(start: CGRect, from origin: CGPoint, to point: CGPoint,
                         minimum: CGSize = CGSize(width: 180, height: 120)) -> CGRect {
    let width = max(start.width + (point.x - origin.x), minimum.width)
    let height = max(start.height + (point.y - origin.y), minimum.height)
    return CGRect(x: start.minX, y: start.minY, width: width, height: height)
}

/// Whether these modifiers are the ones a modifier-drag waits for. Everything the
/// system already uses for dragging stays untouched, so the combination has to be
/// exactly the one chosen.
public func isModifierDrag(flags: Int, wanted: Int) -> Bool {
    wanted != 0 && flags == wanted
}
