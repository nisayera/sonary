import CoreGraphics
import Foundation

/// What a mark on a screenshot is.
public enum AnnotationKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case arrow, rectangle, ellipse, highlight, redact, text

    public var id: String { rawValue }

    /// A redaction has to hide what is under it, so it is always filled.
    public var isFilled: Bool { self == .highlight || self == .redact }
}

/// One mark: its kind, the rectangle it was drawn in, and its text if it has any.
public struct Annotation: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: AnnotationKind
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    /// Line width or, for text, the point size.
    public var weight: Double

    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint,
                text: String = "", weight: Double = 4) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.weight = weight
    }

    /// The rectangle the mark covers, whichever way it was drawn.
    public var frame: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

/// A mark too small to have been meant. An arrow is kept at a shorter length than a
/// box, since a short arrow still points somewhere.
public func isAnnotationWorthKeeping(_ annotation: Annotation) -> Bool {
    let frame = annotation.frame
    switch annotation.kind {
    case .arrow: return max(frame.width, frame.height) >= 8
    case .text: return !annotation.text.isEmpty
    default: return frame.width >= 6 && frame.height >= 6
    }
}

/// How coarse a redaction's blocks are: big enough that nothing can be read back out,
/// and never smaller than one block over the whole area.
public func redactionBlockSize(for frame: CGRect, divisions: Double = 8) -> Double {
    let side = min(frame.width, frame.height)
    guard side > 0 else { return 1 }
    return max(side / divisions, 6)
}

/// The size of the exported picture, with a margin around it for a background.
public func exportSize(image: CGSize, margin: Double) -> CGSize {
    CGSize(width: image.width + margin * 2, height: image.height + margin * 2)
}

/// The part of the shot that is exported: the crop, kept inside the picture and on whole
/// points, or all of it when there is no crop or the crop is too small to have been meant.
public func exportCropArea(_ crop: CGRect?, imageSize: CGSize) -> CGRect {
    let full = CGRect(origin: .zero, size: imageSize)
    guard let crop else { return full }
    let clipped = crop.standardized.integral.intersection(full)
    guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else { return full }
    return clipped
}

/// Where a watermark goes: the bottom right corner of the picture, a little way in.
public func watermarkOrigin(textSize: CGSize, in area: CGRect, padding: Double) -> CGPoint {
    CGPoint(x: max(area.minX + padding, area.maxX - textSize.width - padding), y: area.minY + padding)
}

/// Where the picture sits inside the exported one.
public func exportImageOrigin(margin: Double) -> CGPoint {
    CGPoint(x: margin, y: margin)
}

/// The background a screenshot is exported on.
public enum ExportBackground: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, white, dark, accent

    public var id: String { rawValue }

    /// No margin without a background, so a plain export is pixel for pixel the shot.
    public func margin(_ chosen: Double) -> Double { self == .none ? 0 : chosen }
}

/// The marks after an undo. Undoing on an empty list is not an error, it just does
/// nothing, so a user mashing ⌘Z cannot get into trouble.
public func undoing(_ annotations: [Annotation]) -> [Annotation] {
    guard !annotations.isEmpty else { return annotations }
    return annotations.dropLast()
}

/// The file name a saved screenshot gets, stamped with the time it was taken.
public func screenshotFileName(now: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Sonary \(formatter.string(from: now))"
}
