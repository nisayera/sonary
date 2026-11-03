import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.registry.isEnabled(model.monitor.id), let text = model.monitor.menuBarText() {
            Text(text).monospacedDigit()
        } else {
            Image(systemName: "waveform")
        }
    }
}
