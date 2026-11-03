import SwiftUI
import SonaryCore
import SonaryUI

struct PopoverView: View {
    let model: AppModel

    var body: some View {
        let active = model.registry.modules.filter { model.registry.isEnabled($0.id) }
        VStack(alignment: .leading, spacing: Spacing.s) {
            if active.isEmpty {
                ContentUnavailableView("No modules active", systemImage: "square.grid.2x2",
                                       description: Text("Turn modules on in Settings."))
            } else {
                ForEach(active, id: \.id) { module in
                    if let content = module.makePopoverView() {
                        content
                    } else {
                        Label {
                            Text(module.title)
                        } icon: {
                            Image(systemName: module.symbol)
                        }
                    }
                }
            }
            Divider()
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Button {
                model.updates.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            .disabled(!model.updates.canCheckForUpdates)
            Button("Quit Sonary") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(Spacing.m)
        .frame(width: 320)
    }
}
