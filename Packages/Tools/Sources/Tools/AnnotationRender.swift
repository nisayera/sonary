import AppKit

/// Draws the marks onto a copy of the shot and gives back a new picture: cropped, put on
/// a background and signed with a watermark when asked. Nothing is drawn into the
/// original, so the editor can always start over.
@MainActor
func renderAnnotated(_ image: NSImage, annotations: [Annotation],
                     background: ExportBackground, margin: Double,
                     crop: CGRect? = nil, watermark: String = "",
                     accent: NSColor = .systemPink) -> NSImage? {
    // The marks go on the whole shot first, so a crop never cuts what a redaction reads.
    guard let marked = bitmapImage(size: image.size, {
        image.draw(in: CGRect(origin: .zero, size: image.size))
        for annotation in annotations {
            draw(annotation, offset: .zero, in: image, accent: accent)
        }
    }) else { return nil }
    let area = exportCropArea(crop, imageSize: image.size)
    let inset = background.margin(margin)
    let size = exportSize(image: area.size, margin: inset)
    return bitmapImage(size: size) {
        switch background {
        case .none: break
        case .white: NSColor.white.setFill()
        case .dark: NSColor(white: 0.12, alpha: 1).setFill()
        case .accent: accent.withAlphaComponent(0.85).setFill()
        }
        if background != .none { CGRect(origin: .zero, size: size).fill() }
        let placed = CGRect(origin: exportImageOrigin(margin: inset), size: area.size)
        marked.draw(in: placed, from: area, operation: .copy, fraction: 1)
        let text = watermark.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { drawWatermark(text, in: placed) }
    }
}

/// A picture of the given size, drawn by `body` into a fresh bitmap.
@MainActor
private func bitmapImage(size: CGSize, _ body: () -> Void) -> NSImage? {
    guard size.width >= 1, size.height >= 1,
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width.rounded()),
                                        pixelsHigh: Int(size.height.rounded()), bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    body()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let result = NSImage(size: size)
    result.addRepresentation(bitmap)
    return result
}

/// White text with a soft shadow, so it reads on light and dark shots alike.
@MainActor
private func drawWatermark(_ text: String, in area: CGRect) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = CGSize(width: 0, height: -1)
    let size = max(12, min(area.width, area.height) * 0.035)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        .shadow: shadow,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(at: watermarkOrigin(textSize: string.size(), in: area, padding: size * 0.8))
}

@MainActor
private func draw(_ annotation: Annotation, offset: CGPoint, in image: NSImage, accent: NSColor) {
    let frame = annotation.frame.offsetBy(dx: offset.x, dy: offset.y)
    switch annotation.kind {
    case .rectangle:
        accent.setStroke()
        let path = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
        path.lineWidth = annotation.weight
        path.stroke()
    case .ellipse:
        accent.setStroke()
        let path = NSBezierPath(ovalIn: frame)
        path.lineWidth = annotation.weight
        path.stroke()
    case .highlight:
        NSColor.systemYellow.withAlphaComponent(0.35).setFill()
        frame.fill(using: .multiply)
    case .redact:
        drawRedaction(frame, of: image, offset: offset)
    case .arrow:
        accent.setStroke()
        drawArrow(from: CGPoint(x: annotation.start.x + offset.x, y: annotation.start.y + offset.y),
                  to: CGPoint(x: annotation.end.x + offset.x, y: annotation.end.y + offset.y),
                  weight: annotation.weight)
    case .text:
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(annotation.weight * 4, 14), weight: .semibold),
            .foregroundColor: accent,
        ]
        NSAttributedString(string: annotation.text, attributes: attributes)
            .draw(at: CGPoint(x: frame.minX, y: frame.minY))
    }
}

/// A redaction has to destroy what was there, not cover it: the area is drawn back at
/// a fraction of its size and scaled up, so the pixels are gone for good.
@MainActor
private func drawRedaction(_ frame: CGRect, of image: NSImage, offset: CGPoint) {
    let block = redactionBlockSize(for: frame)
    let source = frame.offsetBy(dx: -offset.x, dy: -offset.y)
    let small = CGSize(width: max(1, frame.width / block), height: max(1, frame.height / block))
    guard let shrunk = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(small.width),
                                        pixelsHigh: Int(small.height), bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let shrinking = NSGraphicsContext(bitmapImageRep: shrunk) else {
        NSColor.black.setFill()
        frame.fill()
        return
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = shrinking
    image.draw(in: CGRect(origin: .zero, size: small), from: source, operation: .copy, fraction: 1)
    shrinking.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.current?.imageInterpolation = .none
    shrunk.draw(in: frame, from: .zero, operation: .copy, fraction: 1,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    NSGraphicsContext.current?.imageInterpolation = .default
}

private func drawArrow(from start: CGPoint, to end: CGPoint, weight: Double) {
    let path = NSBezierPath()
    path.lineWidth = weight
    path.move(to: start)
    path.line(to: end)
    // The head is a pair of short lines turned back from the direction of travel.
    let angle = atan2(end.y - start.y, end.x - start.x)
    let head = max(weight * 4, 12.0)
    for turn in [Double.pi * 0.82, -Double.pi * 0.82] {
        path.move(to: end)
        path.line(to: CGPoint(x: end.x + cos(angle + turn) * head,
                              y: end.y + sin(angle + turn) * head))
    }
    path.lineCapStyle = .round
    path.stroke()
}
