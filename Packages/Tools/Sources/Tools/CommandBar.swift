import AppKit
import SonaryUI
import SwiftUI

struct CommandItem: Identifiable {
    enum Kind { case app(URL), snippet(Snippet), action(() -> Void), copyText(String) }
    let id: String
    let title: String
    let symbol: String?
    let kind: Kind
}

final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌥Space: a floating search field that opens apps, inserts snippets and runs Sonary's tools.
@MainActor
final class CommandBarController {
    private let model: ToolsModel
    private var panel: CommandBarPanel?
    private var apps: [CommandItem] = []

    init(model: ToolsModel) {
        self.model = model
    }

    func show() {
        if apps.isEmpty { apps = Self.loadApps() }
        if panel == nil {
            let panel = CommandBarPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 380),
                                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                        backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = true
            self.panel = panel
        }
        guard let panel else { return }
        let root = CommandBarView(items: items(), close: { [weak self] in self?.close() },
                                  run: { [weak self] item in self?.run(item) })
        panel.contentView = NSHostingView(rootView: root)
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - 310, y: screen.frame.minY + screen.frame.height * 0.55))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func items() -> [CommandItem] {
        let tools: [CommandItem] = [
            CommandItem(id: "ocr", title: String(localized: "Copy text from screen", bundle: .module), symbol: "text.viewfinder",
                        kind: .action { [weak model] in model?.recognizeText() }),
            CommandItem(id: "color", title: String(localized: "Pick a color", bundle: .module), symbol: "eyedropper",
                        kind: .action { [weak model] in model?.pickColor() }),
            CommandItem(id: "shot", title: String(localized: "Screenshot to clipboard", bundle: .module), symbol: "camera.viewfinder",
                        kind: .action { [weak model] in model?.screenshotToClipboard() }),
        ]
        let snippets = model.settings.snippets.map {
            CommandItem(id: "snippet-\($0.id)", title: $0.title, symbol: "text.quote", kind: .snippet($0))
        }
        return tools + snippets + apps
    }

    func run(_ item: CommandItem) {
        close()
        switch item.kind {
        case let .app(url): NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case let .snippet(snippet): model.insert(snippet)
        case let .action(action): action()
        case let .copyText(text):
            model.copy(text)
            model.lastResultText = String(localized: "Copied \(text)", bundle: .module)
        }
    }

    private static func loadApps() -> [CommandItem] {
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var result: [CommandItem] = []
        for folder in folders {
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                guard seen.insert(name).inserted else { continue }
                result.append(CommandItem(id: url.path, title: name, symbol: nil, kind: .app(url)))
            }
        }
        return result
    }
}

struct CommandBarView: View {
    let items: [CommandItem]
    let close: () -> Void
    let run: (CommandItem) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    /// Maths, unit conversions and emoji come first; they only appear when the query really is one.
    private var instantResults: [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var found: [CommandItem] = []
        if let value = evaluateExpression(q) {
            found.append(CommandItem(id: "calc", title: "\(q) = \(value)", symbol: "equal.square",
                                     kind: .copyText(value)))
        }
        if let value = convertUnits(q) {
            found.append(CommandItem(id: "unit", title: "\(q) = \(value)", symbol: "arrow.left.arrow.right",
                                     kind: .copyText(value)))
        }
        for item in searchEmoji(q).prefix(5) {
            found.append(CommandItem(id: "emoji-\(item.emoji)", title: "\(item.emoji)  \(item.name)", symbol: nil,
                                     kind: .copyText(item.emoji)))
        }
        return found
    }

    private var results: [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(items.prefix(8)) }
        let matches = items.compactMap { item in matchScore(q, in: item.title).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let instant = instantResults
        return Array((instant + matches).prefix(8))
    }

    var body: some View {
        let list = results
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query) { Text("Search apps, snippets and tools", bundle: .module) }
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused)
                .onSubmit { if list.indices.contains(selected) { run(list[selected]) } }
                .onChange(of: query) { _, _ in selected = 0 }
            Divider()
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    icon(for: item).frame(width: 24, height: 24)
                    Text(item.title).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(index == selected ? Color.sonaryAccent.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { run(item) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 620, height: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(list.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    @ViewBuilder
    private func icon(for item: CommandItem) -> some View {
        if case let .app(url) = item.kind {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else if item.symbol == nil {
            Text(String(item.title.prefix(2))).font(.system(size: 18))
        } else {
            Image(systemName: item.symbol ?? "sparkles").foregroundStyle(Color.sonaryAccent)
        }
    }
}
