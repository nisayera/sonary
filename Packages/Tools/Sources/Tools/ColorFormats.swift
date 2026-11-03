import Foundation

public enum ColorFormat: String, CaseIterable, Codable, Sendable {
    case hex, rgb, hsl, swiftUI
}

/// The colour under the picker, written the way the chosen format wants it.
public func formatColor(red: Double, green: Double, blue: Double, format: ColorFormat) -> String {
    func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    let r = clamp(red), g = clamp(green), b = clamp(blue)
    switch format {
    case .hex:
        return hexColor(red: r, green: g, blue: b)
    case .rgb:
        return "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))"
    case .hsl:
        let (h, s, l) = hsl(r: r, g: g, b: b)
        return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    case .swiftUI:
        return "Color(red: \(formatNumber((r * 1000).rounded() / 1000)), " +
            "green: \(formatNumber((g * 1000).rounded() / 1000)), " +
            "blue: \(formatNumber((b * 1000).rounded() / 1000)))"
    }
}

func hsl(r: Double, g: Double, b: Double) -> (hue: Double, saturation: Double, lightness: Double) {
    let maximum = max(r, g, b), minimum = min(r, g, b)
    let lightness = (maximum + minimum) / 2
    guard maximum != minimum else { return (0, 0, lightness) }
    let delta = maximum - minimum
    let saturation = lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
    var hue: Double
    if maximum == r {
        hue = (g - b) / delta + (g < b ? 6 : 0)
    } else if maximum == g {
        hue = (b - r) / delta + 2
    } else {
        hue = (r - g) / delta + 4
    }
    hue *= 60
    return (hue, saturation, lightness)
}
