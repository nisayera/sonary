import SonaryUI
import SwiftUI

/// The mouse tab of the menu panel: the switches used most, in sections that open in place,
/// like every other tab.
struct MousePopoverView: View {
    let module: MouseModule
    /// The sections that are open, as a comma-separated list; each opens and closes on its own.
    @AppStorage("panel.mouse.open") private var open = "scrolling,pointer"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDisclosure(symbol: "arrow.up.and.down", title: Text("Scrolling", bundle: .module),
                            isExpanded: $open.opens("scrolling")) {
                PanelGroup {
                    toggle("arrow.up.and.down.text.horizontal", "Linear scrolling", \.linearScroll)
                    toggle("water.waves", "Smooth scrolling", \.smoothScroll)
                    toggle("arrow.up.arrow.down", "Reverse mouse wheel direction", \.reverseScroll)
                    toggle("arrow.left.arrow.right", "Reverse sideways scrolling", \.reverseHorizontalScroll)
                }
            }
            PanelDisclosure(symbol: "cursorarrow", title: Text("Pointer", bundle: .module),
                            isExpanded: $open.opens("pointer")) {
                PanelGroup {
                    toggle("cursorarrow.motionlines", "Turn off pointer acceleration", \.disableAcceleration)
                }
            }
        }
    }

    private func toggle(_ symbol: String, _ title: LocalizedStringKey,
                        _ keyPath: WritableKeyPath<MouseSettings, Bool>) -> some View {
        PanelToggleRow(
            symbol: symbol,
            title: Text(title, bundle: .module),
            isOn: Binding(
                get: { module.settings[keyPath: keyPath] },
                set: { value in module.update { $0[keyPath: keyPath] = value } }
            )
        )
    }
}
