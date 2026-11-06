import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A list of apps kept by bundle identifier, shown with their icons and names, with a remove
/// button for each and an Add button that asks for an app in /Applications. For exception
/// lists: apps a feature leaves alone, or the only ones it applies to.
public struct AppListEditor: View {
    @Binding private var bundleIDs: [String]
    private let addTitle: Text
    private let removeLabel: Text

    public init(bundleIDs: Binding<[String]>, addTitle: Text, removeLabel: Text) {
        self._bundleIDs = bundleIDs
        self.addTitle = addTitle
        self.removeLabel = removeLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bundleIDs, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    Image(nsImage: appIcon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: appDisplayName(for: bundleID))
                        .lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        bundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(removeLabel)
                }
            }
            Button {
                addApp()
            } label: {
                Label { addTitle } icon: { Image(systemName: "plus") }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) else { continue }
            bundleIDs.append(id)
        }
    }
}

/// An app's name for its bundle identifier, or the identifier when the app is not installed.
public func appDisplayName(for bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

/// An app's icon for its bundle identifier, or a generic app icon when it is not installed.
public func appIcon(for bundleID: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        return NSWorkspace.shared.icon(for: .application)
    }
    return NSWorkspace.shared.icon(forFile: url.path)
}
