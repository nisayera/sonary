import Charts
import SonaryUI
import SwiftUI

struct MetricCard: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    var series: [Double] = []
    var domain: ClosedRange<Double> = 0...1

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                }
                if series.count > 1 {
                    Chart(Array(series.enumerated()), id: \.offset) { point in
                        LineMark(x: .value("t", point.offset), y: .value("v", point.element))
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: domain)
                    .frame(height: 36)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
