import SonaryUI
import SwiftUI

func keepAwakeTitle(_ duration: KeepAwakeDuration) -> LocalizedStringKey {
    switch duration {
    case .fifteenMinutes: "15 min"
    case .oneHour: "1 h"
    case .twoHours: "2 h"
    case .indefinitely: "Until I turn it off"
    }
}

struct SoundPopoverView: View {
    let model: SoundModel
    /// The time picked for "awake until", an hour from when the panel opened.
    @State private var awakeUntil = Date().addingTimeInterval(3600)

    var body: some View {
        SettingsCard(Text("Output", bundle: .module)) {
            devicePicker(model.outputs, selected: model.defaultOutput) { model.selectOutput($0) }
            if let volume = model.outputVolume {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { volume }, set: { model.setOutputVolume($0) }), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Volume", bundle: .module))
            }
        }
        SettingsCard(Text("Microphone", bundle: .module)) {
            devicePicker(model.inputs, selected: model.defaultInput) { model.selectInput($0) }
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(.secondary)
                ProgressView(value: model.micMuted ? 0 : model.inputLevel)
                    .progressViewStyle(.linear)
                    .tint(model.inputLevel > 0.85 ? .orange : Color.sonaryAccent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Microphone level", bundle: .module))
            .task {
                model.startWatchingInputLevel()
                // The meter stops when the panel closes, so nothing holds the microphone.
                try? await Task.sleep(for: .seconds(3600))
            }
            .onDisappear { model.stopWatchingInputLevel() }
            if let volume = model.inputVolume {
                HStack {
                    Image(systemName: "mic").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { volume }, set: { model.setInputVolume($0) }), in: 0...1)
                    Image(systemName: "mic.fill").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Input level", bundle: .module))
            }
            SettingsToggleRow(symbol: model.micMuted ? "mic.slash.fill" : "mic.fill",
                              title: Text("Mute microphone", bundle: .module),
                              caption: model.settings.micMuteShortcut ? Text(verbatim: "⌃⌥M") : nil,
                              isOn: Binding(get: { model.micMuted }, set: { _ in model.toggleMicMute() }))
        }
        SettingsCard(Text("Playing now", bundle: .module)) {
            if model.playingApps.isEmpty {
                Text("Nothing is playing.", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.playingApps) { process in
                HStack(spacing: 8) {
                    if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(verbatim: model.appName(for: process)).lineLimit(1)
                    Spacer()
                    Button { model.reveal(process) } label: { Text("Show", bundle: .module) }
                        .controlSize(.small)
                }
            }
            Text("Sonary can see which apps are playing. Setting each one's volume needs to take over the audio path, which Sonary does not do.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            // Refreshed while the panel is open, and not otherwise.
            while !Task.isCancelled {
                model.refreshPlayingApps()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        SettingsCard(Text("Keep awake", bundle: .module)) {
            if model.keepAwakeActive {
                HStack {
                    if let ends = model.keepAwakeEndsAt {
                        Text("Awake until \(ends.formatted(date: .omitted, time: .shortened))", bundle: .module)
                    } else {
                        Text("Awake until you turn it off", bundle: .module)
                    }
                    Spacer()
                    Button { model.setKeepAwake(nil, on: false) } label: { Text("Stop", bundle: .module) }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                        Button { model.setKeepAwake(duration, on: true) } label: {
                            Text(keepAwakeTitle(duration), bundle: .module).lineLimit(1)
                        }
                    }
                }
                .controlSize(.small)
                HStack(spacing: 6) {
                    Text("Until", bundle: .module).font(.callout)
                    DatePicker(selection: $awakeUntil, displayedComponents: .hourAndMinute) { EmptyView() }
                        .labelsHidden()
                    Button { model.keepAwake(until: awakeUntil) } label: { Text("Start", bundle: .module) }
                    Spacer()
                }
                .controlSize(.small)
                HStack(spacing: 6) {
                    if !model.settings.keepAwakeApp.isEmpty {
                        Button { model.keepAwakeWhileAppRuns(model.settings.keepAwakeApp) } label: {
                            Text("While \(model.appName(for: model.settings.keepAwakeApp)) runs", bundle: .module)
                                .lineLimit(1)
                        }
                    }
                    Button { model.keepAwakeWhilePowered() } label: {
                        Text("While plugged in", bundle: .module).lineLimit(1)
                    }
                    if model.hasExternalDisplay {
                        Button { model.keepAwakeWhileDisplayConnected() } label: {
                            Text("While a display is attached", bundle: .module).lineLimit(1)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func devicePicker(_ list: [AudioDevice], selected: UInt32?, choose: @escaping (UInt32) -> Void) -> some View {
        Picker(selection: Binding(get: { selected ?? 0 }, set: { choose($0) })) {
            ForEach(list) { Text($0.name).tag($0.id) }
        } label: { EmptyView() }
            .labelsHidden()
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
        SettingsCard(Text("Keep awake", bundle: .module)) {
            SettingsToggleRow(symbol: "laptopcomputer", title: Text("Stay awake with the lid closed", bundle: .module),
                              caption: Text("Holds the stronger assertion, so an external display keeps working.", bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeWithClosedLid },
                                            set: { value in model.update { $0.keepAwakeWithClosedLid = value } }))
            SettingsToggleRow(symbol: "cup.and.saucer", title: Text("Show a cup in the menu bar while awake", bundle: .module),
                              caption: Text("Its menu says until when, and stops keep awake.", bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeMenuBarIcon },
                                            set: { value in model.update { $0.keepAwakeMenuBarIcon = value } }))
            SettingsToggleRow(symbol: "cursorarrow.motionlines", title: Text("Nudge the pointer now and then", bundle: .module),
                              caption: Text("Moves it by one pixel and back every minute or so, for apps that mark you away when there is no input. Needs Accessibility.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.keepAwakeNudgesPointer },
                                            set: { value in model.update { $0.keepAwakeNudgesPointer = value } }))
            HStack {
                Text("Keep awake while this app runs", bundle: .module)
                Spacer()
                Picker(selection: Binding(get: { model.settings.keepAwakeApp },
                                          set: { value in model.update { $0.keepAwakeApp = value } })) {
                    Text("None", bundle: .module).tag("")
                    ForEach(model.runningApps) { Text($0.name).tag($0.id) }
                } label: { EmptyView() }
                    .labelsHidden()
                    .frame(maxWidth: 180)
            }
        }
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Switch speakers and microphones, change the volume, mute the microphone and keep your Mac awake from the menu panel's sound tab.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
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
