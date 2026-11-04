import SonaryUI
import SwiftUI

struct NotchSettingsView: View {
    let model: NotchModel

    var body: some View {
        SettingsCard(Text("Widgets", bundle: .module)) {
            ForEach(NotchWidget.allCases, id: \.self) { widget in
                SettingsToggleRow(
                    symbol: widget.symbol,
                    title: Text(widgetTitle(widget), bundle: .module),
                    caption: caption(for: widget),
                    isOn: Binding(get: { model.settings.isOn(widget) }, set: { model.setWidget(widget, on: $0) })
                )
            }
        }
        SettingsCard(Text("Display", bundle: .module)) {
            SettingsToggleRow(
                symbol: "display",
                title: Text("Show on displays without a notch", bundle: .module),
                caption: Text("Draws a small island at the top centre of the main display.", bundle: .module),
                isOn: Binding(get: { model.settings.showOnScreensWithoutNotch },
                              set: { model.setShowOnScreensWithoutNotch($0) })
            )
        }
        SettingsCard(Text("Usage", bundle: .module)) {
            Text("Move the pointer onto the island to open it. Click it to keep it open, click anywhere else to close it.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func caption(for widget: NotchWidget) -> Text? {
        switch widget {
        case .music: Text("Music and Spotify, with play, pause and skip.", bundle: .module)
        case .calendar: Text("Today's remaining events. Asks for calendar access.", bundle: .module)
        case .timer: Text("Quick countdowns with a sound at the end.", bundle: .module)
        case .downloads: Text("Your newest downloads; click to open or drag them out.", bundle: .module)
        case .batteries: Text("Mouse, keyboard, trackpad and headphones.", bundle: .module)
        case .shelf: Text("Park files on the notch and drag them out again.", bundle: .module)
        case .camera: Text("A live picture from the front camera, for checking yourself before a call.", bundle: .module)
        }
    }
}
