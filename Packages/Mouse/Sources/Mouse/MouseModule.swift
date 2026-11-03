import Foundation
import Observation
import SonaryCore
import SwiftUI

@MainActor
@Observable
public final class MouseModule: SonaryModule {
    public let id = "mouse"
    public let title = LocalizedStringResource("Mouse", bundle: .atURL(Bundle.module.bundleURL))
    public let symbol = "computermouse"
    public var requiredPermissions: [SonaryPermission] { [.accessibility] }

    public private(set) var settings: MouseSettings

    @ObservationIgnored private let store: MouseSettingsStore
    @ObservationIgnored private let acceleration: AccelerationGuard
    @ObservationIgnored private var controller: EventTapController?

    public init(
        defaults: UserDefaults = .standard,
        acceleration: any AccelerationControlling = IOHIDAccelerationControl()
    ) {
        store = MouseSettingsStore(defaults: defaults)
        self.acceleration = AccelerationGuard(control: acceleration, defaults: defaults)
        settings = store.load()
    }

    public func start() async throws {
        guard controller == nil else { return }
        acceleration.recoverIfNeeded()
        let controller = EventTapController(settings: settings)
        try controller.start()
        self.controller = controller
        if settings.disableAcceleration { acceleration.disable() }
    }

    public func stop() async {
        controller?.stop()
        controller = nil
        acceleration.restore()
    }

    /// Changes settings, saves them and applies them to the running module.
    public func update(_ change: (inout MouseSettings) -> Void) {
        let before = settings
        var changed = settings
        change(&changed)
        settings = changed
        store.save(changed)
        guard let controller else { return }
        controller.update(settings: changed)
        if changed.disableAcceleration != before.disableAcceleration {
            if changed.disableAcceleration { acceleration.disable() } else { acceleration.restore() }
        }
    }

    public func makeSettingsView() -> AnyView { AnyView(MouseSettingsView(module: self)) }
}
