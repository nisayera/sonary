import AppKit

/// A cup in the menu bar while keep awake runs. Its menu says until when, and stops it.
@MainActor
final class KeepAwakeStatusItem: NSObject {
    private var item: NSStatusItem?
    private var stop: () -> Void = {}

    func show(endsAt: Date?, stop: @escaping () -> Void) {
        self.stop = stop
        let item = item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        let label = String(localized: "Keep awake", bundle: .module)
        item.button?.image = NSImage(systemSymbolName: "cup.and.heat.waves.fill", accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: label)
        let menu = NSMenu()
        let status = if let endsAt {
            String(localized: "Awake until \(endsAt.formatted(date: .omitted, time: .shortened))", bundle: .module)
        } else {
            String(localized: "Awake until you turn it off", bundle: .module)
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let stopItem = NSMenuItem(title: String(localized: "Stop", bundle: .module), action: #selector(stopNow),
                                  keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        item.menu = menu
    }

    func hide() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func stopNow() { stop() }
}
