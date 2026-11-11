import SwiftUI
import SonaryCore
import SonaryUI
import Vorssaint

@main
struct SonaryApp: App {
    @State private var model: AppModel

    init() {
        // A run asked only to clean up after another one does that and exits here.
        SonaryEngine.runHelperIfRequestedAndExit()
        // Never a second Sonary next to a running one: two would fight over the event taps,
        // the menu bar and the settings.
        if !AppModel.isRunningTests, Self.anotherCopyIsRunning { exit(EXIT_SUCCESS) }
        _model = State(initialValue: AppModel(startUpdater: !AppModel.isRunningTests))
    }

    private static var anotherCopyIsRunning: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != own && !$0.isTerminated }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
                .task {
                    model.registerPanelShortcut()
                    await model.registry.startEnabled()
                }
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
