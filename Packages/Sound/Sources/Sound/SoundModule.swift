import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class SoundModule: SonaryModule {
    public let id = "sound"
    public let title = LocalizedStringResource("Sound", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "speaker.wave.2"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: SoundModel

    public init(defaults: UserDefaults = .standard) {
        model = SoundModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(SoundSettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }
    public func makePopoverView() -> AnyView? { AnyView(SoundPopoverView(model: model)) }
}
