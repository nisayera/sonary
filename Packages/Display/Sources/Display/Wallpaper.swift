import AppKit
import ImageIO
import SonaryUI
import SwiftUI

/// Files that can be a desktop picture. The system's dynamic and moving wallpapers are
/// packages of their own and are left to System Settings.
public func isWallpaperFile(_ name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    return ["heic", "jpg", "jpeg", "png", "tiff", "tif"].contains(ext) && !name.hasPrefix(".")
}

/// The folders the gallery looks in: the system's pictures, then the user's own.
public func wallpaperFolders(extra: [String], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
    let system = ["/System/Library/Desktop Pictures", "/Library/Desktop Pictures"].map { URL(fileURLWithPath: $0) }
    let own = [home.appendingPathComponent("Pictures/Wallpapers")] + extra.map { URL(fileURLWithPath: $0) }
    var seen = Set<String>()
    return (system + own).filter { seen.insert($0.standardizedFileURL.path).inserted }
}

/// Browses desktop pictures and sets one on every display, or on one.
@MainActor
@Observable
final class WallpaperGallery {
    private(set) var pictures: [URL] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    func load(extraFolders: [String]) async {
        let folders = wallpaperFolders(extra: extraFolders)
        pictures = await Task.detached { () -> [URL] in
            folders.flatMap { folder -> [URL] in
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                return items.filter { isWallpaperFile($0.lastPathComponent) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
        }.value
    }

    /// A small picture, made once and kept while the page is open.
    func thumbnail(for url: URL) async {
        guard thumbnails[url] == nil else { return }
        let image = await Task.detached { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: 320,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image { thumbnails[url] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
    }

    /// Sets the picture on one display, or on all of them when `screen` is nil. False when
    /// macOS refused it.
    @discardableResult
    func set(_ url: URL, on screen: NSScreen?) -> Bool {
        let screens = screen.map { [$0] } ?? NSScreen.screens
        var done = true
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                done = false
            }
        }
        return done
    }
}

struct WallpaperCard: View {
    let model: DisplayModel
    @State private var gallery = WallpaperGallery()
    @State private var screenIndex = -1
    @State private var failed = false

    var body: some View {
        SettingsCard(Text("Wallpaper", bundle: .module)) {
            HStack {
                if NSScreen.screens.count > 1 {
                    Picker(selection: $screenIndex) {
                        Text("All displays", bundle: .module).tag(-1)
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Text(verbatim: screen.localizedName).tag(index)
                        }
                    } label: { EmptyView() }
                        .settingsControl()
                }
                Spacer()
                Button { addFolder() } label: { Text("Add folder…", bundle: .module) }
            }
            if gallery.pictures.isEmpty {
                Text("No pictures found. Add a folder with your own.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(gallery.pictures, id: \.self) { url in
                            Button {
                                let screens = NSScreen.screens
                                failed = !gallery.set(url, on: screens.indices.contains(screenIndex) ? screens[screenIndex] : nil)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
                                    if let image = gallery.thumbnails[url] {
                                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                    }
                                }
                                .frame(height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(Text(verbatim: url.deletingPathExtension().lastPathComponent))
                            .task { await gallery.thumbnail(for: url) }
                        }
                    }
                }
                .frame(height: 230)
            }
            if failed {
                SettingsWarning(Text("macOS did not take that picture.", bundle: .module))
            }
        }
        .task(id: model.settings.wallpaperFolders) { await gallery.load(extraFolders: model.settings.wallpaperFolders) }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { settings in
            if !settings.wallpaperFolders.contains(url.path) { settings.wallpaperFolders.append(url.path) }
        }
    }
}
