import AppKit
import SonaryUI
import SwiftUI

/// The sound tab of the menu panel: output, microphone and what is playing, each a section
/// that opens in place, like every other tab.
struct SoundPopoverView: View {
    let model: SoundModel
    /// The sections that are open, as a comma-separated list; each opens and closes on its own.
    @AppStorage("panel.sound.open") private var open = "output,microphone"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDisclosure(symbol: "speaker.wave.2", title: Text("Output", bundle: .module),
                            isExpanded: $open.opens("output")) {
                if let volume = model.outputVolume { Text(verbatim: percentLabel(volume)) }
            } content: {
                PanelGroup {
                    PanelRow(symbol: "hifispeaker", title: Text("Device", bundle: .module)) {
                        devicePicker(model.outputs, selected: model.defaultOutput) { model.selectOutput($0) }
                    }
                    if let volume = model.outputVolume {
                        PanelSliderRow(symbol: volume == 0 ? "speaker.slash" : "speaker.wave.2",
                                       title: Text("Volume", bundle: .module),
                                       value: Binding(get: { volume }, set: { model.setOutputVolume($0) }),
                                       valueText: percentLabel(volume))
                    }
                }
            }
            PanelDisclosure(symbol: "mic", title: Text("Microphone", bundle: .module),
                            isExpanded: $open.opens("microphone")) {
                if model.micMuted { Text("Muted", bundle: .module).foregroundStyle(.orange) }
            } content: {
                PanelGroup {
                    PanelRow(symbol: "mic", title: Text("Device", bundle: .module)) {
                        devicePicker(model.inputs, selected: model.defaultInput) { model.selectInput($0) }
                    }
                    PanelRow(symbol: "waveform", title: Text("Microphone level", bundle: .module)) {
                        ProgressView(value: model.micMuted ? 0 : model.inputLevel)
                            .progressViewStyle(.linear)
                            .tint(model.inputLevel > 0.85 ? .orange : Color.sonaryAccent)
                            .frame(width: 110)
                    }
                    .task {
                        model.startWatchingInputLevel()
                        // The meter stops when the section closes, so nothing holds the microphone.
                        try? await Task.sleep(for: .seconds(3600))
                    }
                    .onDisappear { model.stopWatchingInputLevel() }
                    if let volume = model.inputVolume {
                        PanelSliderRow(symbol: "dial.medium", title: Text("Input level", bundle: .module),
                                       value: Binding(get: { volume }, set: { model.setInputVolume($0) }),
                                       valueText: percentLabel(volume))
                    }
                    PanelToggleRow(symbol: model.micMuted ? "mic.slash" : "mic",
                                   title: Text("Mute microphone", bundle: .module),
                                   caption: model.micMuteShortcutText.isEmpty
                                       ? nil : Text(verbatim: model.micMuteShortcutText),
                                   isOn: Binding(get: { model.micMuted }, set: { _ in model.toggleMicMute() }))
                }
            }
            PanelDisclosure(symbol: "music.note.list", title: Text("Playing now", bundle: .module),
                            isExpanded: $open.opens("playing")) {
                if !model.playingApps.isEmpty { Text(verbatim: "\(model.playingApps.count)") }
            } content: {
                if model.playingApps.isEmpty {
                    PanelEmptyState(symbol: "music.note", text: Text("Nothing is playing.", bundle: .module))
                } else {
                    PanelGroup {
                        ForEach(model.playingApps) { process in
                            HStack(spacing: PanelMetrics.rowIconSpacing) {
                                if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
                                    Image(nsImage: icon).resizable()
                                        .frame(width: PanelMetrics.rowIconWidth, height: PanelMetrics.rowIconWidth)
                                }
                                Text(verbatim: model.appName(for: process))
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Button { model.reveal(process) } label: { Text("Show", bundle: .module) }
                                    .controlSize(.small)
                            }
                            .panelRowInsets()
                        }
                    }
                }
                PanelNote(Text("Sonary can see which apps are playing. Setting each one's volume needs to take over the audio path, which Sonary does not do.",
                               bundle: .module))
            }
        }
        .task {
            // Refreshed while the panel is open, and not otherwise.
            while !Task.isCancelled {
                model.refreshPlayingApps()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
    }

    private func devicePicker(_ list: [AudioDevice], selected: UInt32?, choose: @escaping (UInt32) -> Void) -> some View {
        Picker(selection: Binding(get: { selected ?? 0 }, set: { choose($0) })) {
            ForEach(list) { Text($0.name).tag($0.id) }
        } label: { EmptyView() }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 170)
    }
}

struct SoundSettingsView: View {
    let model: SoundModel

    var body: some View {
        SettingsCard(Text("Shortcuts", bundle: .module)) {
            SettingsToggleRow(symbol: "mic.slash", title: Text("Mute the microphone with ⌃⌥M", bundle: .module),
                              caption: Text("Works in every app, also during calls.", bundle: .module),
                              isOn: Binding(get: { model.settings.micMuteShortcut },
                                            set: { value in model.update { $0.micMuteShortcut = value } }))
        }
        SettingsCard(Text("Headphones", bundle: .module)) {
            SettingsToggleRow(symbol: "speaker.wave.2", title: Text("Switch output with ⌃⌥O", bundle: .module),
                              caption: Text("Moves to the next speaker or headphones.", bundle: .module),
                              isOn: Binding(get: { model.settings.outputSwitchShortcut },
                                            set: { value in model.update { $0.outputSwitchShortcut = value } }))
            SettingsToggleRow(symbol: "speaker.slash",
                              title: Text("Turn the volume down when headphones are unplugged", bundle: .module),
                              caption: Text("Keeps the speakers from suddenly blaring.", bundle: .module),
                              isOn: Binding(get: { model.settings.volumeAfterUnplug > 0 },
                                            set: { value in model.update { $0.volumeAfterUnplug = value ? 0.25 : 0 } }))
        }
        SettingsCard(Text("Preferred devices", bundle: .module)) {
            Text("When one of these appears, Sonary switches to it. The higher it is in the list, the more it is wanted. A device you pick by hand stays until another one from the list connects.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            DevicePriorityEditor(title: Text("Output", bundle: .module), names: model.settings.outputPriority,
                                 known: model.outputs.map(\.name)) { names in model.update { $0.outputPriority = names } }
            DevicePriorityEditor(title: Text("Input", bundle: .module), names: model.settings.inputPriority,
                                 known: model.inputs.map(\.name)) { names in model.update { $0.inputPriority = names } }
        }
        SettingsCard(Text("Microphone", bundle: .module)) {
            SettingsToggleRow(symbol: "circle.fill",
                              title: Text("Show a dot while the microphone is live", bundle: .module),
                              caption: Text("Appears in the top right corner when something is picked up.", bundle: .module),
                              isOn: Binding(get: { model.settings.micIndicator },
                                            set: { value in model.update { $0.micIndicator = value } }))
        }
        SettingsCard(Text("Media keys", bundle: .module)) {
            SettingsToggleRow(symbol: "playpause", title: Text("Keep the media keys from opening Music", bundle: .module),
                              caption: Text("While a player is running, Sonary passes the key to it instead.", bundle: .module),
                              isOn: Binding(get: { model.settings.mediaKeyGuard },
                                            set: { value in model.update { $0.mediaKeyGuard = value } }))
            if model.mediaKeysNeedAccessibility {
                SettingsWarning(Text("Sonary needs Accessibility for this. Allow it under System Settings → Privacy & Security → Accessibility, then switch this off and on again.", bundle: .module))
            }
        }
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Switch speakers and microphones, change the volume and mute the microphone from the menu panel's sound tab.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The dot that says the microphone is live.
struct MicIndicatorDot: View {
    var body: some View {
        Circle()
            .fill(Color.orange)
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// An ordered list of device names: move one up, take one out, add one that is connected.
struct DevicePriorityEditor: View {
    let title: Text
    let names: [String]
    /// The devices connected now, offered for adding.
    let known: [String]
    let change: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title.font(.callout.weight(.medium))
                Spacer()
                let addable = known.filter { !names.contains($0) }
                Menu {
                    ForEach(addable, id: \.self) { name in
                        Button { change(names + [name]) } label: { Text(verbatim: name) }
                    }
                } label: { Text("Add", bundle: .module) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(addable.isEmpty)
            }
            if names.isEmpty {
                Text("None yet", bundle: .module).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(names.enumerated()), id: \.element) { index, name in
                HStack(spacing: 8) {
                    Text(verbatim: "\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(verbatim: name).lineLimit(1)
                    if !known.contains(name) {
                        Text("Not connected", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { change(movedUp(names, at: index)) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel(Text("Move up", bundle: .module))
                    Button { change(names.filter { $0 != name }) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove", bundle: .module))
                }
                .font(.system(size: 12))
            }
        }
    }
}

/// The list with the entry at `index` swapped with the one above it.
func movedUp(_ names: [String], at index: Int) -> [String] {
    guard index > 0, names.indices.contains(index) else { return names }
    var result = names
    result.swapAt(index, index - 1)
    return result
}
