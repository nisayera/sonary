import SwiftUI

/// Sonary's icon in the menu bar, or the symbol chosen for it. The monitor's readouts are menu
/// bar items of their own next to it.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage(menuBarSymbolKey) private var symbol = ""

    var body: some View {
        Group {
            if symbol.isEmpty {
                Image("MenuBarIcon")
            } else {
                Image(systemName: symbol)
            }
        }
        .accessibilityLabel(Text("Sonary"))
        .onAppear { model.openSettingsWindow = { openSettings() } }
    }
}
