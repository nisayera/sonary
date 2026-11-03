import SwiftUI

@MainActor
public protocol SonaryModule: AnyObject {
    var id: String { get }
    var title: LocalizedStringResource { get }
    var symbol: String { get }
    var requiredPermissions: [SonaryPermission] { get }
    func start() async throws
    func stop() async
    func makeSettingsView() -> AnyView
}
