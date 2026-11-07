import AppKit
import SonaryUI
import SwiftUI

/// ⌃⌥R: a ring of actions around the pointer. Move out to a wedge and click, or press Escape.
@MainActor
final class RadialMenuController {
    private var panel: NSPanel?
    private let size = 320.0

    func show(items: [RadialItem], run: @escaping (QuickAction) -> Void, launch: @escaping (RadialLaunch) -> Void,
              open: @escaping (RadialProfile) -> Void, back: @escaping () -> Void) {
        guard !items.isEmpty else { return }
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
            items: items,
            pick: { [weak self] item in
                switch item {
                case .action(let action):
                    self?.close()
                    run(action)
                case .launch(let target):
                    self?.close()
                    launch(target)
                case .profile(let profile):
                    open(profile)
                case .back:
                    back()
                case nil:
                    self?.close()
                }
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
    let items: [RadialItem]
    let pick: (RadialItem?) -> Void
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
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let offset = radialItemOffset(index: index, count: items.count, radius: 108)
                let isHovered = hovered == index
                RadialWedgeIcon(item: item)
                    .frame(width: 52, height: 52)
                    .background(isHovered ? Color.sonaryAccent : Color.black.opacity(0.45), in: Circle())
                    .scaleEffect(isHovered ? 1.12 : 1)
                    .offset(x: offset.x, y: -offset.y)
                    .accessibilityLabel(radialLabel(item))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(point):
                hovered = radialSelection(center: center, point: point, count: items.count)
            case .ended:
                hovered = nil
            }
        }
        .onTapGesture {
            if let hovered, items.indices.contains(hovered) { pick(items[hovered]) } else { pick(nil) }
        }
        .onExitCommand { pick(nil) }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// A wedge's picture: the app's or file's own icon where there is one, a symbol otherwise.
struct RadialWedgeIcon: View {
    let item: RadialItem

    var body: some View {
        switch item {
        case .launch(.app(let path)), .launch(.file(let path)):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
        default:
            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

func radialLabel(_ item: RadialItem) -> Text {
    switch item {
    case .action(let action): Text(quickActionTitle(action), bundle: .module)
    case .launch(let launch): Text(verbatim: launch.title)
    case .profile(let profile): Text(verbatim: profile.name)
    case .back: Text("Back", bundle: .module)
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
    case .scrollingShot: "Scrolling screenshot"
    }
}
