import AppKit
import SonaryUI
import SwiftUI

final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A small floating palette of favourite tools next to the pointer. A click runs one and
/// closes it; Escape or a click elsewhere closes it too.
@MainActor
final class QuickPanelController {
    private var panel: QuickPanelWindow?

    func toggle(actions: [QuickAction], run: @escaping (QuickAction) -> Void) {
        if panel?.isVisible == true {
            close()
            return
        }
        guard !actions.isEmpty else { return }
        let columns = min(4, actions.count)
        let rows = (actions.count + columns - 1) / columns
        let size = CGSize(width: CGFloat(columns) * 84 + 20, height: CGFloat(rows) * 78 + 20)
        let panel = panel ?? QuickPanelWindow(contentRect: CGRect(origin: .zero, size: size),
                                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                               defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: QuickPanelView(actions: actions, columns: columns, pick: { [weak self] action in
            self?.close()
            // Let the palette go first, so the action works on what was in front.
            Task { @MainActor in run(action) }
        }, cancel: { [weak self] in self?.close() }))
        panel.setContentSize(size)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame ?? .zero
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2)
        if screen.width > 0 {
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
            origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }
}

struct QuickPanelView: View {
    let actions: [QuickAction]
    let columns: Int
    let pick: (QuickAction) -> Void
    let cancel: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 6), count: columns), spacing: 6) {
            ForEach(actions) { action in
                Button { pick(action) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: action.symbol).font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.sonaryAccent)
                        Text(quickActionTitle(action), bundle: .module)
                            .font(.system(size: 10, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(width: 78, height: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onExitCommand { cancel() }
    }
}
