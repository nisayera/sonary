import AppKit

/// Stitching two shots means finding where the second one carries on from the first.
/// Rows are compared by a hash each, so a long page costs little to line up.
///
/// Returns how many rows at the top of the next shot are already in the previous one,
/// or nil when they do not overlap at all, in which case the shots are simply joined.
public func overlapRows(previous: [UInt64], next: [UInt64], minimumOverlap: Int = 8) -> Int? {
    guard previous.count >= minimumOverlap, next.count >= minimumOverlap else { return nil }
    // The largest overlap wins, so a page with repeating rows does not stitch too short.
    var candidate = min(previous.count, next.count)
    while candidate >= minimumOverlap {
        let tail = previous.suffix(candidate)
        let head = next.prefix(candidate)
        if Array(tail) == Array(head) { return candidate }
        candidate -= 1
    }
    return nil
}

/// The height of the finished picture: the first shot in full, then each later shot
/// without the part already seen.
public func stitchedHeight(shots: [Int], overlaps: [Int?]) -> Int {
    guard let first = shots.first else { return 0 }
    var total = first
    for (index, height) in shots.enumerated().dropFirst() {
        let overlap = overlaps.indices.contains(index - 1) ? (overlaps[index - 1] ?? 0) : 0
        total += max(0, height - overlap)
    }
    return total
}

/// A shot that adds nothing means the page stopped scrolling, so capturing can stop.
public func hasStoppedScrolling(previous: [UInt64], next: [UInt64]) -> Bool {
    !previous.isEmpty && previous == next
}

/// One hash per row of a bitmap, for lining shots up.
@MainActor
func rowHashes(of bitmap: NSBitmapImageRep) -> [UInt64] {
    guard let data = bitmap.bitmapData else { return [] }
    let bytesPerRow = bitmap.bytesPerRow
    let height = bitmap.pixelsHigh
    let width = min(bitmap.pixelsWide * (bitmap.bitsPerPixel / 8), bytesPerRow)
    return (0..<height).map { row in
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let start = row * bytesPerRow
        // Every fourth byte is enough to tell rows apart and a quarter of the work.
        for offset in stride(from: 0, to: width, by: 4) {
            hash = (hash ^ UInt64(data[start + offset])) &* 0x1000_0000_01b3
        }
        return hash
    }
}

/// Takes a region, scrolls it, takes it again, and joins the shots into one tall
/// picture. Stops when the page has nothing more to show or the limit is reached.
@MainActor
func captureScrolling(region: CGRect, shots limit: Int = 12,
                      capture: @MainActor @escaping (CGRect) async -> NSImage?) async -> NSImage? {
    var images: [NSBitmapImageRep] = []
    var hashes: [[UInt64]] = []
    for step in 0..<max(1, limit) {
        guard let image = await capture(region),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { break }
        let rows = rowHashes(of: bitmap)
        if let last = hashes.last, hasStoppedScrolling(previous: last, next: rows) { break }
        images.append(bitmap)
        hashes.append(rows)
        guard step < limit - 1 else { break }
        scrollOnce(in: region, by: bitmap.pixelsHigh)
        try? await Task.sleep(for: .milliseconds(320))
    }
    return join(images, hashes: hashes)
}

/// Scrolls the window under the region by about one screenful.
@MainActor
private func scrollOnce(in region: CGRect, by pixels: Int) {
    let centre = CGPoint(x: region.midX, y: region.midY)
    guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                             mouseCursorPosition: centre, mouseButton: .left) else { return }
    move.post(tap: .cghidEventTap)
    guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: Int32(-max(40, pixels - 40)), wheel2: 0, wheel3: 0) else { return }
    scroll.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    scroll.post(tap: .cghidEventTap)
}

@MainActor
private func join(_ bitmaps: [NSBitmapImageRep], hashes: [[UInt64]]) -> NSImage? {
    guard let first = bitmaps.first else { return nil }
    guard bitmaps.count > 1 else {
        let image = NSImage(size: CGSize(width: first.pixelsWide, height: first.pixelsHigh))
        image.addRepresentation(first)
        return image
    }
    let overlaps = (1..<bitmaps.count).map { overlapRows(previous: hashes[$0 - 1], next: hashes[$0]) }
    let height = stitchedHeight(shots: bitmaps.map(\.pixelsHigh), overlaps: overlaps)
    let width = first.pixelsWide
    guard height > 0, let canvas = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: canvas) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // Drawn from the bottom up, since the canvas counts from the bottom.
    var y = height
    for (index, bitmap) in bitmaps.enumerated() {
        let overlap = index == 0 ? 0 : (overlaps[index - 1] ?? 0)
        let kept = max(0, bitmap.pixelsHigh - overlap)
        guard kept > 0 else { continue }
        y -= kept
        bitmap.draw(in: CGRect(x: 0, y: y, width: width, height: bitmap.pixelsHigh),
                    from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: nil)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: CGSize(width: width, height: height))
    image.addRepresentation(canvas)
    return image
}
