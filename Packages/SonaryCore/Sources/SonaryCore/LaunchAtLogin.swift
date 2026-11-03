import Foundation
import Observation
import ServiceManagement

public protocol LoginItemControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

public struct SMAppServiceLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
@Observable
public final class LaunchAtLoginModel {
    public private(set) var isEnabled: Bool
    public private(set) var errorMessage: String?
    @ObservationIgnored private let controller: any LoginItemControlling

    public init(controller: any LoginItemControlling = SMAppServiceLoginItem()) {
        self.controller = controller
        self.isEnabled = controller.isEnabled
    }

    public func set(_ on: Bool) {
        do {
            try controller.setEnabled(on)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        isEnabled = controller.isEnabled
    }
}
