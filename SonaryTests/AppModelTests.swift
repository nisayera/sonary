import Foundation
import SonaryCore
import Testing
@testable import Sonary

@MainActor
struct AppModelTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sonary.apptests.\(UUID().uuidString)")!
    }

    @Test func monitorToggleEnablesAndPersists() async {
        let defaults = makeDefaults()
        let first = AppModel(defaults: defaults, startUpdater: false)
        await first.registry.setEnabled("monitor", true)
        #expect(first.registry.isEnabled("monitor"))
        #expect(first.registry.failures["monitor"] == nil)

        let second = AppModel(defaults: defaults, startUpdater: false)
        #expect(second.registry.isEnabled("monitor"))

        await first.registry.setEnabled("monitor", false)
        #expect(!first.registry.isEnabled("monitor"))
    }

    @Test func mouseModuleIsRegisteredAndNeedsAccessibility() {
        let model = AppModel(defaults: makeDefaults(), startUpdater: false)
        let module = model.registry.modules.first { $0.id == "mouse" }
        #expect(module?.requiredPermissions == [.accessibility])
        #expect(!model.registry.isEnabled("mouse"))
    }

    @Test func onboardingFlagPersists() {
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, startUpdater: false)
        #expect(!model.onboardingCompleted)
        model.completeOnboarding()
        #expect(AppModel(defaults: defaults, startUpdater: false).onboardingCompleted)
    }
}
