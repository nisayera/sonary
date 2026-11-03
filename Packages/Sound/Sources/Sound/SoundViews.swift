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
            SettingsToggleRow(symbol: model.micMuted ? "mic.slash.fill" : "mic.fill",
                              title: Text("Mute microphone", bundle: .module),
                              caption: model.settings.micMuteShortcut ? Text(verbatim: "⌃⌥M") : nil,
                              isOn: Binding(get: { model.micMuted }, set: { _ in model.toggleMicMute() }))
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
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Switch speakers and microphones, change the volume, mute the microphone and keep your Mac awake from the menu panel's sound tab.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
