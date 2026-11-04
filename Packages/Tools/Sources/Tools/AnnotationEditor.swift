import AppKit
import SonaryUI
import SwiftUI

/// The window that opens on a fresh screenshot: draw on it, hide what should not be
/// seen, put it on a background, then copy or save.
@MainActor
final class AnnotationEditorController {
    private var window: NSWindow?

    func open(_ image: NSImage, report: @escaping (String) -> Void) {
        close()
        let view = AnnotationEditorView(image: image, report: report) { [weak self] in self?.close() }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Screenshot", bundle: .module)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

struct AnnotationEditorView: View {
    let image: NSImage
    let report: (String) -> Void
    let dismiss: () -> Void

    @State private var annotations: [Annotation] = []
    @State private var kind: AnnotationKind = .arrow
    @State private var drawing: Annotation?
    @State private var background: ExportBackground = .none
    @State private var margin: Double = 48
    @State private var pendingText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.m)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker(selection: $kind) {
                ForEach(AnnotationKind.allCases) { kind in
                    Image(systemName: symbol(kind)).tag(kind)
                        .accessibilityLabel(Text(title(kind), bundle: .module))
                }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            if kind == .text {
                TextField(text: $pendingText) { Text("Text", bundle: .module) }
                    .frame(width: 140)
            }
            Spacer()
            Picker(selection: $background) {
                ForEach(ExportBackground.allCases) { Text(backgroundTitle($0), bundle: .module).tag($0) }
            } label: { EmptyView() }
                .labelsHidden()
                .frame(width: 130)
            Button { annotations = undoing(annotations) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(annotations.isEmpty)
                .help(Text("Undo the last mark", bundle: .module))
            Button { copy() } label: { Text("Copy", bundle: .module) }
            Button { save() } label: { Text("Save", bundle: .module) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.s)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / max(image.size.width, 1),
                            proxy.size.height / max(image.size.height, 1), 1)
            let shown = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: shown.width, height: shown.height)
                Canvas { context, _ in
                    for annotation in annotations + [drawing].compactMap({ $0 }) {
                        stroke(annotation, in: &context, scale: scale)
                    }
                }
                .frame(width: shown.width, height: shown.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            // Views grow downwards, the picture upwards.
                            let start = flip(value.startLocation, height: shown.height, scale: scale)
                            let now = flip(value.location, height: shown.height, scale: scale)
                            drawing = Annotation(kind: kind, start: start, end: now,
                                                 text: pendingText, weight: 4)
                        }
                        .onEnded { _ in
                            if let drawing, isAnnotationWorthKeeping(drawing) { annotations.append(drawing) }
                            drawing = nil
                        }
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    /// A point in the view turned into one in the picture.
    private func flip(_ point: CGPoint, height: Double, scale: Double) -> CGPoint {
        CGPoint(x: point.x / scale, y: (height - point.y) / scale)
    }

    private func stroke(_ annotation: Annotation, in context: inout GraphicsContext, scale: Double) {
        let frame = annotation.frame
        let rect = CGRect(x: frame.minX * scale, y: (image.size.height - frame.maxY) * scale,
                          width: frame.width * scale, height: frame.height * scale)
        let colour = Color.sonaryAccent
        switch annotation.kind {
        case .rectangle: context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(colour), lineWidth: 3)
        case .ellipse: context.stroke(Path(ellipseIn: rect), with: .color(colour), lineWidth: 3)
        case .highlight: context.fill(Path(rect), with: .color(.yellow.opacity(0.35)))
        case .redact: context.fill(Path(rect), with: .color(.black.opacity(0.9)))
        case .text:
            context.draw(Text(verbatim: annotation.text).foregroundStyle(colour),
                         at: CGPoint(x: rect.minX, y: rect.minY))
        case .arrow:
            var path = Path()
            path.move(to: CGPoint(x: annotation.start.x * scale,
                                  y: (image.size.height - annotation.start.y) * scale))
            path.addLine(to: CGPoint(x: annotation.end.x * scale,
                                     y: (image.size.height - annotation.end.y) * scale))
            context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private func rendered() -> NSImage? {
        renderAnnotated(image, annotations: annotations, background: background, margin: margin)
    }

    private func copy() {
        guard let result = rendered() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([result])
        report(String(localized: "Screenshot copied to the clipboard.", bundle: .module))
        dismiss()
    }

    private func save() {
        guard let result = rendered(),
              let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first,
              let tiff = result.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let name = uniqueMediaName(base: screenshotFileName(now: Date()), extension: "png") {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let url = folder.appendingPathComponent(name)
        guard (try? png.write(to: url)) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        report(String(localized: "Saved to \(url.lastPathComponent)", bundle: .module))
        dismiss()
    }

    private func symbol(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .redact: "eye.slash"
        case .text: "textformat"
        }
    }

    private func title(_ kind: AnnotationKind) -> LocalizedStringKey {
        switch kind {
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        case .redact: "Hide"
        case .text: "Text"
        }
    }

    private func backgroundTitle(_ background: ExportBackground) -> LocalizedStringKey {
        switch background {
        case .none: "No background"
        case .white: "White"
        case .dark: "Dark"
        case .accent: "Sonary pink"
        }
    }
}
