import AppKit

/// One menu bar item per metric, for those who want each value on its own. The items hold
/// text only; the Sonary icon stays the way into the panel.
@MainActor
final class MonitorStatusItems {
    private var items: [ReadoutMetric: NSStatusItem] = [:]

    /// Shows these texts, adding and removing items so each metric has exactly one.
    func show(_ readings: [(metric: ReadoutMetric, text: String)]) {
        let wanted = Set(readings.map(\.metric))
        for (metric, item) in items where !wanted.contains(metric) {
            NSStatusBar.system.removeStatusItem(item)
            items[metric] = nil
        }
        // Added right to left, so the first metric ends up leftmost.
        for reading in readings.reversed() {
            let item = items[reading.metric] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[reading.metric] = item
            item.button?.title = reading.text
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }
    }

    func removeAll() {
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
        items = [:]
    }
}
