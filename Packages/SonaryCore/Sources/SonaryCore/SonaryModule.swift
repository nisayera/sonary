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
    /// Optional content shown in the menu bar popover while the module is enabled.
    func makePopoverView() -> AnyView?
    /// The bundle with the module's texts, so the settings search can find an option by
    /// what it says.
    var resourceBundle: Bundle? { get }
}

public extension SonaryModule {
    func makePopoverView() -> AnyView? { nil }
    var resourceBundle: Bundle? { nil }
}

/// The order of the menu panel's tabs: the ones the user placed first, in that order, then
/// the rest as they come, without the hidden ones.
public func orderedPanelTabs(available: [String], order: [String], hidden: Set<String>) -> [String] {
    let placed = order.filter { available.contains($0) }
    let rest = available.filter { !placed.contains($0) }
    return (placed + rest).filter { !hidden.contains($0) }
}

/// The texts of a module's string table worth searching: options and their explanations,
/// not single words, format strings or whole paragraphs.
public func searchableTexts(_ table: [String: String]) -> [String] {
    Array(Set(table.values.filter { text in
        text.count >= 6 && text.count <= 120 && !text.contains("%") && text.contains(" ")
    })).sorted()
}
