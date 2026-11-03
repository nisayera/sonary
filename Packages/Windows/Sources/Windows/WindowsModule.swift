import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class WindowsModule: SonaryModule {
    public let id = "windows"
    public let title = LocalizedStringResource("Windows", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "macwindow.on.rectangle"
    public var requiredPermissions: [SonaryPermission] { [.accessibility] }

    public let model: WindowsModel

    public init(defaults: UserDefaults = .standard) {
        model = WindowsModel(defaults: defaults)
    }

    public func start() async throws { model.start() }
    public func stop() async { model.stop() }

    public func makeSettingsView() -> AnyView { AnyView(WindowsSettingsView(model: model)) }
}
