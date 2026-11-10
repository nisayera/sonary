import Foundation
import Observation
import SonaryCore
import SonaryUI
import SwiftUI
import Vorssaint

/// The Dynamic Island. It is Vorssaint's island, taken over as it is (see `Vendor/Vorssaint` and
/// NOTICE); Sonary switches it on and off, hands it the accent colour and shows its settings.
@MainActor
@Observable
final class IslandModule: SonaryModule {
    let id = "notch"
    let title = LocalizedStringResource("Notch")
    let symbol = "capsule.portrait.tophalf.filled"
    var requiredPermissions: [SonaryPermission] { [] }

    func start() async throws {
        SonaryIsland.setAccent(Color.sonaryAccent)
        SonaryIsland.start()
    }

    func stop() async {
        SonaryIsland.stop()
    }

    func makeSettingsView() -> AnyView {
        AnyView(SonaryIsland.settingsView().tint(Color.sonaryAccent))
    }
}
