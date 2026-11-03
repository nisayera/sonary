import AppKit

/// Tracks the frontmost app's bundle ID so the event-tap thread can read it without touching AppKit.
final class FrontmostApp: @unchecked Sendable {
    private let box = Locked<String?>(nil)
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    var bundleID: String? { box.withValue { $0 } }

    @MainActor
    func start() {
        box.withValue { $0 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [box] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            box.withValue { $0 = id }
        }
    }

    @MainActor
    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
