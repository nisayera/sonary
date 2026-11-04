import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case png, jpeg, heic, tiff

    public var id: String { rawValue }

    public var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }
}

/// The size an image is scaled to when a longest edge is asked for. Zero or a size
/// already below the limit leaves the image alone.
public func scaledSize(width: Int, height: Int, longestEdge: Int) -> (width: Int, height: Int) {
    guard longestEdge > 0, max(width, height) > longestEdge, width > 0, height > 0 else {
        return (width, height)
    }
    let factor = Double(longestEdge) / Double(max(width, height))
    return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
}

/// The file an export is written to, next to the original and never over it.
public func exportURL(for source: URL, format: ImageFormat, exists: (String) -> Bool) -> URL {
    let base = source.deletingPathExtension().lastPathComponent
    let name = uniqueMediaName(base: base, extension: format.fileExtension, exists: exists)
    return source.deletingLastPathComponent().appendingPathComponent(name)
}

/// "Shot.png", then "Shot 2.png", and so on.
public func uniqueMediaName(base: String, extension ext: String, exists: (String) -> Bool) -> String {
    var name = "\(base).\(ext)"
    var number = 2
    while exists(name) {
        name = "\(base) \(number).\(ext)"
        number += 1
    }
    return name
}

/// Converts an image file, optionally scaling it down and stamping a corner with text.
/// Returns the file it wrote.
public func convertImage(at source: URL, to format: ImageFormat, longestEdge: Int = 0,
                         watermark: String = "", quality: Double = 0.9) throws -> URL {
    guard let original = NSImage(contentsOf: source) else { throw MediaError.unreadable }
    let pixel = original.representations.first.map { (Int($0.pixelsWide), Int($0.pixelsHigh)) }
        ?? (Int(original.size.width), Int(original.size.height))
    let target = scaledSize(width: pixel.0, height: pixel.1, longestEdge: longestEdge)
    let size = NSSize(width: target.width, height: target.height)

    // Drawn into an explicit bitmap context rather than with lockFocus, so this also
    // works off the main thread.
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: target.width,
                                        pixelsHigh: target.height, bitsPerSample: 8, samplesPerPixel: 4,
                                        hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw MediaError.cannotEncode }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    original.draw(in: NSRect(origin: .zero, size: size))
    if !watermark.isEmpty { draw(watermark: watermark, in: size) }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let data: Data?
    switch format {
    case .png: data = bitmap.representation(using: .png, properties: [:])
    case .jpeg: data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    case .tiff: data = bitmap.representation(using: .tiff, properties: [:])
    case .heic: data = heicData(from: bitmap, quality: quality)
    }
    guard let data else { throw MediaError.cannotEncode }
    let url = exportURL(for: source, format: format) { FileManager.default.fileExists(
        atPath: source.deletingLastPathComponent().appendingPathComponent($0).path) }
    try data.write(to: url)
    return url
}

private func heicData(from bitmap: NSBitmapImageRep, quality: Double) -> Data? {
    guard let cgImage = bitmap.cgImage else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output, UTType.heic.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, cgImage,
                               [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
}

private func draw(watermark text: String, in size: NSSize) {
    let fontSize = max(12, min(size.width, size.height) * 0.05)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        .shadow: {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = fontSize / 4
            return shadow
        }(),
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    let inset = fontSize / 2
    string.draw(at: NSPoint(x: size.width - bounds.width - inset, y: inset))
}

/// Shrinks a video by re-encoding it at a smaller preset. Returns the file it wrote.
public func compressVideo(at source: URL, preset: String = AVAssetExportPreset1280x720) async throws -> URL {
    let asset = AVURLAsset(url: source)
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
        throw MediaError.cannotEncode
    }
    let name = uniqueMediaName(base: source.deletingPathExtension().lastPathComponent + " small",
                               extension: "mp4") {
        FileManager.default.fileExists(atPath: source.deletingLastPathComponent().appendingPathComponent($0).path)
    }
    let url = source.deletingLastPathComponent().appendingPathComponent(name)
    try await session.export(to: url, as: .mp4)
    return url
}

public enum MediaError: Error { case unreadable, cannotEncode }
