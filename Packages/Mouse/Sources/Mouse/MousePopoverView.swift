import SonaryUI
import SwiftUI

/// Quick switches for the menu bar panel.
struct MousePopoverView: View {
    let module: MouseModule

    var body: some View {
        SettingsCard(Text("Mouse", bundle: .module)) {
            toggle("arrow.up.and.down.text.horizontal", "Linear scrolling", \.linearScroll)
            toggle("water.waves", "Smooth scrolling", \.smoothScroll)
            toggle("arrow.up.arrow.down", "Reverse mouse wheel direction", \.reverseScroll)
            toggle("cursorarrow.motionlines", "Turn off pointer acceleration", \.disableAcceleration)
        }
    }

    private func toggle(_ symbol: String, _ title: LocalizedStringKey, _ keyPath: WritableKeyPath<MouseSettings, Bool>) -> some View {
        SettingsToggleRow(
            symbol: symbol,
            title: Text(title, bundle: .module),
            isOn: Binding(
                get: { module.settings[keyPath: keyPath] },
                set: { value in module.update { $0[keyPath: keyPath] = value } }
            )
        )
    }
}
