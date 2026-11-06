import AppKit
import AVFoundation
import EventKit
import SonaryCore
import SonaryUI
import SwiftUI
import UserNotifications

// MARK: - Features

/// Every module in one place, grouped like the sidebar: what it does, what it needs, on or off.
struct FeaturesPage: View {
    let model: AppModel

    var body: some View {
        let total = model.registry.modules.count
        let on = model.registry.modules.filter { model.registry.isEnabled($0.id) }.count
        SettingsPage {
            SettingsPageHeader(symbol: "square.grid.2x2", title: Text("Features"),
                               subtitle: Text("Turn on only what you use. A module that is off does not load, run in the background or ask for permissions."))
        } content: {
            SettingsCard {
                HStack {
                    Text("\(on) of \(total) modules on")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            for module in model.registry.modules {
                                await model.registry.setEnabled(module.id, false)
                            }
                        }
                    } label: {
                        Text("Turn all off")
                    }
                    .disabled(on == 0)
                }
            }
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let members = category.moduleIDs.compactMap { id in
                    model.registry.modules.first { $0.id == id }
                }
                if !members.isEmpty {
                    SettingsCard(Text(category.title)) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, module in
                            if index > 0 { Divider() }
                            FeatureRow(model: model, module: module)
                        }
                    }
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let model: AppModel
    let module: any SonaryModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: module.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(module.title).fontWeight(.medium)
                        ForEach(module.requiredPermissions, id: \.self) { permission in
                            Badge(text: permissionTitle(permission))
                        }
                    }
                    Text(ModuleInfo.summary(for: module.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    model.settingsPage = .module(module.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(Text("Settings…"))
                .accessibilityLabel(Text("Settings…"))
                Toggle(isOn: Binding(
                    get: { model.registry.isEnabled(module.id) },
                    set: { on in Task { await model.registry.setEnabled(module.id, on) } }
                )) { Text(module.title) }
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let failure = model.registry.failures[module.id] {
                SettingsWarning(Text(failure))
                    .padding(.leading, 42)
            }
        }
    }
}

/// A small grey tag next to a title, such as the permission a module needs.
private struct Badge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary.opacity(0.7), in: Capsule())
    }
}

// MARK: - Permissions

/// The permissions Sonary can ask for, with what they are for and what in Sonary uses them.
enum PermissionKind: CaseIterable, Hashable {
    case accessibility
    case screenRecording
    case automation
    case notifications
    case calendars
    case camera
    case microphone

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .automation: "gearshape.2"
        case .notifications: "bell.badge"
        case .calendars: "calendar"
        case .camera: "camera"
        case .microphone: "mic"
        }
    }

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        case .automation: String(localized: "Automation")
        case .notifications: String(localized: "Notifications")
        case .calendars: String(localized: "Calendars")
        case .camera: String(localized: "Camera")
        case .microphone: String(localized: "Microphone")
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: String(localized: "Lets Sonary react to clicks and keys, and move windows.")
        case .screenRecording: String(localized: "Lets Sonary capture the screen and show window previews.")
        case .automation: String(localized: "Lets Sonary control Music, Spotify, Finder and System Events. macOS asks once for each app.")
        case .notifications: String(localized: "Lets Sonary warn you about the alerts you turned on.")
        case .calendars: String(localized: "Lets Sonary show today's events.")
        case .camera: String(localized: "Lets Sonary show the camera image.")
        case .microphone: String(localized: "Lets Sonary show how loud the microphone is.")
        }
    }

    var usedBy: String {
        switch self {
        case .accessibility: String(localized: "Mouse, Keyboard, Windows, paste as plain text, media keys, typed snippets, menu commands")
        case .screenRecording: String(localized: "Screenshots, text from screen, screen recording, window previews")
        case .automation: String(localized: "Music in the notch, media keys, Finder helpers, quick toggles")
        case .notifications: String(localized: "Monitor alerts")
        case .calendars: String(localized: "The calendar in the notch")
        case .camera: String(localized: "The camera in the notch, the camera preview")
        case .microphone: String(localized: "The microphone level in the sound panel")
        }
    }

    var settingsURL: URL? {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: URL(string: privacy + "Privacy_Accessibility")
        case .screenRecording: URL(string: privacy + "Privacy_ScreenCapture")
        case .automation: URL(string: privacy + "Privacy_Automation")
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .calendars: URL(string: privacy + "Privacy_Calendars")
        case .camera: URL(string: privacy + "Privacy_Camera")
        case .microphone: URL(string: privacy + "Privacy_Microphone")
        }
    }

    /// Whether macOS has granted it, read without asking. Nil when macOS offers no way to tell
    /// (automation is decided per app).
    @MainActor
    func isGranted() async -> Bool? {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .automation:
            return nil
        case .notifications:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus == .authorized)
                }
            }
        case .calendars:
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }
}

/// What each permission does, what uses it, and whether macOS has granted it, with a way into
/// System Settings. Read again whenever Sonary comes to the front.
struct PermissionsPage: View {
    let model: AppModel
    @State private var granted: [PermissionKind: Bool] = [:]

    var body: some View {
        SettingsPage {
            SettingsPageHeader(symbol: "lock.shield", title: Text("Permissions"),
                               subtitle: Text("What each permission does and what in Sonary uses it. Sonary asks only when you turn on something that needs it."))
        } content: {
            SettingsCard {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider() }
                    PermissionRow(kind: kind, granted: granted[kind])
                }
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        var result: [PermissionKind: Bool] = [:]
        for kind in PermissionKind.allCases {
            if let value = await kind.isGranted() { result[kind] = value }
        }
        granted = result
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let granted: Bool?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: kind.title).font(.headline)
                    status
                }
                Text(verbatim: kind.purpose)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Used by \(kind.usedBy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = kind.settingsURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Open System Settings")
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var status: some View {
        switch granted {
        case .some(true):
            Label { Text("Granted") } icon: { Circle().fill(Color.green).frame(width: 7, height: 7) }
                .font(.caption)
                .foregroundStyle(.secondary)
        case .some(false):
            Label { Text("Not granted") } icon: { Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7, height: 7) }
                .font(.caption)
                .foregroundStyle(.secondary)
        case .none:
            Text("Asked for each app")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
