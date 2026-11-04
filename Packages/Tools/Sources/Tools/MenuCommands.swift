import AppKit
import ApplicationServices

public struct ExternalCommand: Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var run: @MainActor () -> Void

    public init(id: String, title: String, symbol: String, run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.run = run
    }
}

public struct MenuCommand: Equatable, Sendable {
    public var path: [String]
    public var title: String { path.joined(separator: " ▸ ") }
}

/// Menu titles that lead nowhere useful in a search, or that would quit the app behind the user's back.
let skippedMenus: Set<String> = ["Apple", "Window", "Help", "Services"]

/// Keeps the menu items worth offering: enabled, named, not a separator, not from a skipped menu.
public func usefulMenuCommands(_ commands: [MenuCommand], limit: Int = 200) -> [MenuCommand] {
    var seen = Set<String>()
    return commands.filter { command in
        guard let top = command.path.first, !skippedMenus.contains(top) else { return false }
        guard command.path.count >= 2, !command.path.contains(where: { $0.isEmpty || $0 == "-" }) else { return false }
        return seen.insert(command.title).inserted
    }
    .prefix(limit)
    .map { $0 }
}

/// Reads the menu bar of the frontmost app through the accessibility API.
@MainActor
enum MenuBarReader {
    static func commands(for app: NSRunningApplication) -> [(MenuCommand, AXUIElement)] {
        guard AXIsProcessTrusted() else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var found: [(MenuCommand, AXUIElement)] = []
        for menu in children(of: unsafeDowncast(bar, to: AXUIElement.self)) {
            guard let title = title(of: menu), !skippedMenus.contains(title) else { continue }
            collect(from: menu, path: [title], into: &found, depth: 0)
        }
        return found
    }

    private static func collect(from element: AXUIElement, path: [String],
                                into found: inout [(MenuCommand, AXUIElement)], depth: Int) {
        guard depth < 3, found.count < 400 else { return }
        for child in children(of: element) {
            guard let title = title(of: child) else {
                // A menu's items live one level further in, under an unnamed container.
                collect(from: child, path: path, into: &found, depth: depth + 1)
                continue
            }
            let sub = children(of: child)
            if sub.isEmpty {
                found.append((MenuCommand(path: path + [title]), child))
            } else {
                collect(from: child, path: path + [title], into: &found, depth: depth + 1)
            }
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String, !title.isEmpty else { return nil }
        return title
    }

    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}
