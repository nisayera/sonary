import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class KeyboardModule: SonaryModule {
    public let id = "keyboard"
    public let title = LocalizedStringResource("Keyboard", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "keyboard"
    public var requiredPermissions: [SonaryPermission] { [.accessibility] }

    public let model: KeyboardModel

    public init(defaults: UserDefaults = .standard) {
        model = KeyboardModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(KeyboardSettingsView(model: model)) }
}
