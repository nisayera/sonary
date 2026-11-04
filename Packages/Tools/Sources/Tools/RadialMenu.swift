import AppKit
import SonaryUI
import SwiftUI

/// ⌃⌥R: a ring of actions around the pointer. Move out to a wedge and click, or press Escape.
@MainActor
final class RadialMenuController {
    private var panel: NSPanel?
    private let size = 320.0

    func show(actions: [QuickAction], run: @escaping (QuickAction) -> Void) {
        guard !actions.isEmpty else { return }
        close()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        let point = NSEvent.mouseLocation
        panel.setFrameOrigin(CGPoint(x: point.x - size / 2, y: point.y - size / 2))
        panel.contentView = NSHostingView(rootView: RadialMenuView(
            actions: actions,
            pick: { [weak self] action in
                self?.close()
                if let action { run(action) }
            }
        ))
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RadialMenuView: View {
    let actions: [QuickAction]
    let pick: (QuickAction?) -> Void
    @State private var hovered: Int?
    private let size = 320.0

    var body: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        ZStack {
            Circle()
                .fill(.black.opacity(0.28))
                .glassEffect(.regular, in: Circle())
                .frame(width: size, height: size)
            Circle().fill(.black.opacity(0.35)).frame(width: 52, height: 52)
            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let offset = radialItemOffset(index: index, count: actions.count, radius: 108)
                let isHovered = hovered == index
                Image(systemName: action.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(isHovered ? Color.sonaryAccent : Color.black.opacity(0.45), in: Circle())
                    .scaleEffect(isHovered ? 1.12 : 1)
                    .offset(x: offset.x, y: -offset.y)
                    .accessibilityLabel(Text(quickActionTitle(action), bundle: .module))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(point):
                hovered = radialSelection(center: center, point: point, count: actions.count)
            case .ended:
                hovered = nil
            }
        }
        .onTapGesture {
            if let hovered, actions.indices.contains(hovered) { pick(actions[hovered]) } else { pick(nil) }
        }
        .onExitCommand { pick(nil) }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

func quickActionTitle(_ action: QuickAction) -> LocalizedStringKey {
    switch action {
    case .darkMode: "Dark mode"
    case .desktopIcons: "Desktop icons"
    case .emptyTrash: "Empty Trash"
    case .ejectDisks: "Eject disks"
    case .lockScreen: "Lock screen"
    case .cleaningMode: "Cleaning mode"
    case .commandBar: "Command bar"
    case .textFromScreen: "Copy text from screen"
    case .colorPicker: "Pick a color"
    case .screenshot: "Screenshot to clipboard"
    case .pinScreenshot: "Pin a screenshot"
    case .cameraPreview: "Camera mirror"
    case .screenRecording: "Record the screen"
    }
}
