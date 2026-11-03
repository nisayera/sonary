import CoreGraphics
import Foundation

/// Clockwise angle in degrees from straight up, 0..<360.
public func radialAngle(from center: CGPoint, to point: CGPoint) -> Double {
    let dx = Double(point.x - center.x)
    let dy = Double(point.y - center.y)
    let degrees = atan2(dx, dy) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
}

/// Which wedge an angle falls into; the first wedge is centred straight up.
public func radialSector(angle: Double, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let size = 360.0 / Double(count)
    let shifted = (angle + size / 2).truncatingRemainder(dividingBy: 360)
    let normalized = shifted < 0 ? shifted + 360 : shifted
    return Int(normalized / size) % count
}

/// Nil inside the dead zone in the middle, so letting go there cancels instead of picking something.
public func radialSelection(center: CGPoint, point: CGPoint, count: Int, deadZone: Double = 26) -> Int? {
    let distance = hypot(Double(point.x - center.x), Double(point.y - center.y))
    guard distance >= deadZone else { return nil }
    return radialSector(angle: radialAngle(from: center, to: point), count: count)
}

/// Where a wedge's icon sits, measured from the centre.
public func radialItemOffset(index: Int, count: Int, radius: Double) -> CGPoint {
    guard count > 0 else { return .zero }
    let angle = (Double(index) * 360.0 / Double(count)) * .pi / 180
    return CGPoint(x: radius * sin(angle), y: radius * cos(angle))
}
