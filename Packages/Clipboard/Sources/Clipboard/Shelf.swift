import AppKit
import SonaryUI
import SwiftUI
import UniformTypeIdentifiers

/// Something kept on the shelf: a file, a piece of text or a web link.
public enum ShelfItem: Hashable, Sendable, Identifiable {
    case file(URL)
    case text(String)
    case link(URL)

    public var id: String {
        switch self {
        case let .file(url): "file:" + url.path
        case let .text(value): "text:" + value
        case let .link(url): "link:" + url.absoluteString
        }
    }

    /// What the shelf shows for it.
    public var title: String {
        switch self {
        case let .file(url): url.lastPathComponent
        case let .text(value): value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        case let .link(url): url.host() ?? url.absoluteString
        }
    }
}

/// Dropped text becomes a link when it is exactly one http(s) address, and text otherwise.
/// Nil for text with nothing in it.
public func shelfItem(fromText text: String) -> ShelfItem? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
       let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil {
        return .link(url)
    }
    return .text(text)
}

/// A dropped URL: a file stays a file, a web address becomes a link.
public func shelfItem(fromURL url: URL) -> ShelfItem? {
    if url.isFileURL { return .file(url) }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    return .link(url)
}

/// The kinds of things the shelf takes from a drop.
let shelfDropTypes: [UTType] = [.fileURL, .url, .plainText]

/// Reads whatever a drop carries into shelf items: files first, then links, then text.
@MainActor
func loadShelfItems(from providers: [NSItemProvider], add: @escaping @Sendable @MainActor ([ShelfItem]) -> Void) {
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            // These answer on a background thread, so the blocks must not belong to the main actor.
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                guard let url, let item = shelfItem(fromURL: url) else { return }
                Task { @MainActor in add([item]) }
            }
        } else if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { @Sendable text, _ in
                guard let text, let item = shelfItem(fromText: text) else { return }
                Task { @MainActor in add([item]) }
            }
        }
    }
}

/// What a shelf item hands to a drag out of the shelf.
func dragProvider(for item: ShelfItem) -> NSItemProvider {
    switch item {
    case let .file(url): NSItemProvider(contentsOf: url) ?? NSItemProvider()
    case let .text(value): NSItemProvider(object: value as NSString)
    case let .link(url): NSItemProvider(object: url as NSURL)
    }
}

/// One row on the shelf: its icon, its name, sharing and removing.
struct ShelfItemRow: View {
    let item: ShelfItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            icon
            Text(verbatim: item.title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            share
            Button(action: remove) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove", bundle: .module))
        }
        .font(.system(size: 12))
        .contentShape(Rectangle())
        .onDrag { dragProvider(for: item) }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case let .file(url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
        case .text:
            Image(systemName: "text.alignleft").frame(width: 22, height: 22).foregroundStyle(.secondary)
        case .link:
            Image(systemName: "link").frame(width: 22, height: 22).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var share: some View {
        Group {
            switch item {
            case let .file(url): ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            case let .text(value): ShareLink(item: value) { Image(systemName: "square.and.arrow.up") }
            case let .link(url): ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Share", bundle: .module))
    }
}

// MARK: The shelf next to the pointer

final class FloatingShelfWindow: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// A small shelf that appears next to the pointer as soon as files are dragged, so they can
/// be parked on the way. It stays while it holds something and goes when it is empty.
@MainActor
final class FloatingShelf {
    private var panel: FloatingShelfWindow?
    private var monitors: [Any] = []
    /// The drag pasteboard's count when the button went down; a change means a drag began.
    private var dragCountAtMouseDown = 0
    private var hideTask: Task<Void, Never>?
    private weak var model: ClipboardModel?

    static let size = CGSize(width: 240, height: 168)

    func start(model: ClipboardModel) {
        self.model = model
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        hide()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func dragged() {
        guard panel?.isVisible != true else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != dragCountAtMouseDown,
              board.types?.contains(.fileURL) == true else { return }
        show(near: NSEvent.mouseLocation)
    }

    /// Once the drag ends, an empty shelf goes away; one holding files stays.
    private func mouseUp() {
        guard panel?.isVisible == true else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            // Give a drop on the shelf time to arrive.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.model?.shelf.isEmpty ?? true else { return }
            self.hide()
        }
    }

    private func show(near pointer: CGPoint) {
        guard let model else { return }
        hideTask?.cancel()
        if panel == nil {
            let panel = FloatingShelfWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                            defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: FloatingShelfView(model: model, close: { [weak self] in
                self?.hide()
            }))
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame ?? .zero
        panel.setFrameOrigin(floatingShelfOrigin(pointer: pointer, size: Self.size, screen: screen))
        panel.orderFrontRegardless()
    }
}

/// Where the floating shelf goes: up and to the right of the pointer, so it is never under
/// it, and pushed back onto the screen near an edge.
public func floatingShelfOrigin(pointer: CGPoint, size: CGSize, screen: CGRect, gap: CGFloat = 28) -> CGPoint {
    var origin = CGPoint(x: pointer.x + gap, y: pointer.y + gap)
    guard screen.width > 0, screen.height > 0 else { return origin }
    if origin.x + size.width > screen.maxX { origin.x = pointer.x - gap - size.width }
    if origin.y + size.height > screen.maxY { origin.y = pointer.y - gap - size.height }
    origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
    origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
    return origin
}

struct FloatingShelfView: View {
    let model: ClipboardModel
    let close: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shelf", bundle: .module).font(.headline)
                Spacer()
                if !model.shelf.isEmpty {
                    Button { model.clearShelf() } label: { Text("Clear", bundle: .module) }
                        .buttonStyle(.borderless).font(.caption)
                }
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Close", bundle: .module))
            }
            if model.shelf.isEmpty {
                Text("Drop here to keep it for later", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.shelf) { item in
                            ShelfItemRow(item: item) { model.removeFromShelf(item) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: FloatingShelf.size.width, height: FloatingShelf.size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.sonaryAccent, lineWidth: targeted ? 2 : 0)
        )
        .onDrop(of: shelfDropTypes, isTargeted: $targeted) { providers in
            loadShelfItems(from: providers) { model.addToShelf($0) }
            return true
        }
    }
}
