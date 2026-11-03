import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class ToolsModule: SonaryModule {
    public let id = "tools"
    public let title = LocalizedStringResource("Tools", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "wrench.and.screwdriver"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: ToolsModel

    public init(defaults: UserDefaults = .standard) {
        model = ToolsModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(ToolsSettingsView(model: model)) }
    public func makePopoverView() -> AnyView? { AnyView(ToolsPopoverView(model: model)) }
}
