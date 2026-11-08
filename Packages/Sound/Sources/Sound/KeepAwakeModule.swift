import Foundation
import Observation
import SonaryCore
import SwiftUI

/// Keep awake as a module of its own, with its own tab in the menu panel. It shares the sound
/// module's model, which holds the power assertion, so the two never disagree about whether the
/// Mac is being kept awake.
@MainActor
@Observable
public final class KeepAwakeModule: SonaryModule {
    public let id = "awake"
    public let title = LocalizedStringResource("Keep awake", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "cup.and.saucer"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: SoundModel

    public init(model: SoundModel) {
        self.model = model
    }

    public func start() async throws {}
    public func stop() async { model.setKeepAwake(nil) }

    public func makeSettingsView() -> AnyView { AnyView(KeepAwakeSettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }

    public var status: [ModuleStatus] {
        guard model.keepAwakeActive else { return [] }
        return [ModuleStatus(id: "awake", symbol: "cup.and.saucer.fill",
                             title: String(localized: "Keep awake", bundle: .module),
                             value: model.keepAwakeEndsAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "∞")]
    }

    public func makePopoverView() -> AnyView? { AnyView(KeepAwakePopoverView(model: model)) }
}
