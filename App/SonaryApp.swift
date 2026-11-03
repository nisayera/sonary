import SwiftUI
import SonaryCore
import SonaryUI
import Monitor

@main
struct SonaryApp: App {
    var body: some Scene {
        MenuBarExtra("Sonary", systemImage: "waveform") {
            Text("Sonary")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
