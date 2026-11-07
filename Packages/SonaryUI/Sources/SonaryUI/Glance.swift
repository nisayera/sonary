import SwiftUI

/// A symbol on a small rounded square, as System Settings draws its rows: the accent
/// gradient while the thing it stands for is on, a quiet grey while it is off.
public struct IconBadge: View {
    private let symbol: String
    private let isActive: Bool
    private let tint: Color
    private let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(symbol: String, isActive: Bool = true, tint: Color = .sonaryAccent, size: CGFloat = 22) {
        self.symbol = symbol
        self.isActive = isActive
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            .background(shape.fill(isActive ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(PanelColors.control(colorScheme))))
            .overlay(shape.strokeBorder(.white.opacity(isActive ? 0.18 : 0), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A share drawn as a ring with its value inside, for a row of gauges.
public struct StatusRing: View {
    private let fraction: Double
    private let value: String
    private let tint: Color
    private let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, value: String, tint: Color = .sonaryAccent, size: CGFloat = 46) {
        self.fraction = min(max(fraction, 0), 1)
        self.value = value
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().stroke(PanelColors.control(colorScheme), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: max(0.015, fraction))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
            Text(verbatim: value)
                .font(.system(size: size * 0.24, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, size * 0.14)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

/// A gauge with its name under it, for the panel's rows of rings.
public struct LabeledRing: View {
    private let title: Text
    private let fraction: Double
    private let value: String
    private let tint: Color
    private let detail: Text?

    public init(_ title: Text, fraction: Double, value: String, tint: Color = .sonaryAccent, detail: Text? = nil) {
        self.title = title
        self.fraction = fraction
        self.value = value
        self.tint = tint
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 4) {
            StatusRing(fraction: fraction, value: value, tint: tint)
            title
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let detail {
                detail
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One live value in a grid: an icon, a short name and the value, with a thin bar under
/// it when the value is a share.
public struct GlanceTile: View {
    private let symbol: String
    private let title: Text
    private let value: String
    private let fraction: Double?
    private let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    public init(symbol: String, title: Text, value: String, fraction: Double? = nil, tint: Color = .sonaryAccent) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.fraction = fraction
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                IconBadge(symbol: symbol, tint: tint, size: 18)
                title
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(verbatim: value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PanelColors.control(colorScheme))
                        Capsule().fill(tint.gradient)
                            .frame(width: max(3, proxy.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(padded: false)
        .accessibilityElement(children: .combine)
    }
}
