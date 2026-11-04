import AppKit
import ApplicationServices

/// Reads the Dock through the accessibility API: which icon the pointer is over, and
/// which app it belongs to. No private framework, but it does need the Accessibility
/// permission Sonary already asks for.
@MainActor
enum DockReader {
    private static var dockElement: AXUIElement?

    private static func dock() -> AXUIElement? {
        if let dockElement { return dockElement }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        dockElement = element
        return element
    }

    /// Forgets the cached Dock, for when it has been restarted.
    static func reset() { dockElement = nil }

    /// The app whose Dock icon is at this screen point, if any.
    static func app(at point: CGPoint) -> NSRunningApplication? {
        guard let dock = dock() else { return nil }
        var found: AXUIElement?
        var reference: CFTypeRef?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &found) == .success,
              let element = found else { return nil }
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &reference) == .success,
              let role = reference as? String, role == "AXDockItem" else { return nil }
        reference = nil
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &reference) == .success,
              let title = reference as? String, !title.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.localizedName == title
        }
    }
}
