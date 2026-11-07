import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class ClipboardModule: SonaryModule {
    public let id = "clipboard"
    public let title = LocalizedStringResource("Clipboard", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "doc.on.clipboard"
    public var requiredPermissions: [SonaryPermission] { [] }

    public let model: ClipboardModel
    @ObservationIgnored private var running = false

    public init(defaults: UserDefaults = .standard) {
        model = ClipboardModel(defaults: defaults)
    }

    public func start() async throws {
        guard !running else { return }
        running = true
        model.start()
    }

    public func stop() async {
        running = false
        model.stop()
    }

    public func makeSettingsView() -> AnyView { AnyView(ClipboardSettingsView(model: model)) }
    public var resourceBundle: Bundle? { .module }
    public func makePopoverView() -> AnyView? { AnyView(ClipboardPopoverView(model: model)) }
}
