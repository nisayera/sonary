import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class DisplayModule: SonaryModule {
    public let id = "display"
    public let title = LocalizedStringResource("Display", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "sun.max"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: DisplayModel

    public init(defaults: UserDefaults = .standard) {
        model = DisplayModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(DisplaySettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }

    public var status: [ModuleStatus] {
        guard let display = model.displays.first else { return [] }
        return [ModuleStatus(id: "brightness", symbol: "sun.max.fill", title: display.name,
                             value: percentText(display.brightness), fraction: display.brightness)]
    }
    public func makePopoverView() -> AnyView? { AnyView(DisplayPopoverView(model: model)) }
}
