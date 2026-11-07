import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class AppsModule: SonaryModule {
    public let id = "apps"
    public let title = LocalizedStringResource("Apps", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "square.stack.3d.up"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: AppsModel

    public init(defaults: UserDefaults = .standard) {
        model = AppsModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(AppsSettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }

    public var status: [ModuleStatus] {
        let updates = model.outdated.count + model.appUpdates.count
        guard updates > 0 else { return [] }
        return [ModuleStatus(id: "updates", symbol: "arrow.down.app", title: String(localized: "Updates", bundle: .module),
                             value: "\(updates)", level: .warning)]
    }
    public func makePopoverView() -> AnyView? { AnyView(AppsPopoverView(model: model)) }
}
