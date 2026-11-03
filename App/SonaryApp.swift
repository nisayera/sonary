import SwiftUI
import SonaryCore
import SonaryUI

@main
struct SonaryApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Sonary", systemImage: "waveform") {
            PopoverView(model: model)
                .task { await model.registry.startEnabled() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }

        Window("Welcome to Sonary", id: "onboarding") {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.onboardingCompleted ? .suppressed : .presented)
    }
}
