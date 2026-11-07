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
    /// A few live values for the panel's overview and the module's settings page, such as
    /// the CPU load or the volume. Empty while there is nothing worth showing.
    var status: [ModuleStatus] { get }
}

public extension SonaryModule {
    func makePopoverView() -> AnyView? { nil }
    var resourceBundle: Bundle? { nil }
    var status: [ModuleStatus] { [] }
}

/// One live value a module shows at a glance.
public struct ModuleStatus: Identifiable, Equatable, Sendable {
    /// How the value should be read: normal, worth a look, or a problem.
    public enum Level: Sendable, Equatable { case normal, warning, critical }

    public var id: String
    public var symbol: String
    /// A short name, such as "CPU" or "Volume".
    public var title: String
    /// The value as text, such as "42 %" or "AirPods".
    public var value: String
    /// The value as a share, 0...1, when it is one.
    public var fraction: Double?
    public var level: Level

    public init(id: String, symbol: String, title: String, value: String, fraction: Double? = nil,
                level: Level = .normal) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.value = value
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.level = level
    }
}

/// "42 %" for a share, the way the panel writes percentages.
public func percentText(_ fraction: Double) -> String {
    "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
}

/// The level of a share where high is bad, such as a load or a full disk.
public func loadLevel(_ fraction: Double, warning: Double = 0.75, critical: Double = 0.9) -> ModuleStatus.Level {
    fraction >= critical ? .critical : fraction >= warning ? .warning : .normal
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
