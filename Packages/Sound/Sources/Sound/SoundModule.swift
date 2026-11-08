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

    public var status: [ModuleStatus] {
        var items: [ModuleStatus] = []
        if let volume = model.outputVolume {
            let output = model.outputs.first { $0.id == model.defaultOutput }?.name
            items.append(ModuleStatus(id: "volume", symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                      title: output ?? String(localized: "Volume", bundle: .module),
                                      value: percentText(volume), fraction: volume))
        }
        if model.micMuted {
            items.append(ModuleStatus(id: "mic", symbol: "mic.slash.fill", title: String(localized: "Microphone", bundle: .module),
                                      value: String(localized: "Muted", bundle: .module), level: .warning))
        }
        return items
    }
    public func makePopoverView() -> AnyView? { AnyView(SoundPopoverView(model: model)) }
}
