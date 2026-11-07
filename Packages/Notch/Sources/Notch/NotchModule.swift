import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class NotchModule: SonaryModule {
    public let id = "notch"
    public let title = LocalizedStringResource("Notch", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "capsule.portrait.tophalf.filled"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: NotchModel
    @ObservationIgnored private var window: NotchWindowController?

    public init(defaults: UserDefaults = .standard) {
        model = NotchModel(defaults: defaults)
    }

    public func start() async throws {
        guard window == nil else { return }
        model.start()
        let window = NotchWindowController(model: model)
        window.show()
        self.window = window
    }

    public func stop() async {
        window?.close()
        window = nil
        model.stop()
    }

    public func makeSettingsView() -> AnyView {
    public var resourceBundle: Bundle? { .module }
        AnyView(NotchSettingsView(model: model).onChange(of: model.settings.showOnScreensWithoutNotch) { _, _ in
            self.window?.placeOnScreen()
        })
    }
}
