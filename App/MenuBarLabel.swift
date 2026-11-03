import SwiftUI

/// Always the Sonary icon; monitor values only when they are switched on in the monitor settings.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
            if model.registry.isEnabled(model.monitor.id), let text = model.monitor.menuBarText() {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityLabel(Text("Sonary"))
    }
}
