import Foundation
import Testing
@testable import Sonary

@MainActor
struct AppModelTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sonary.apptests.\(UUID().uuidString)")!
    }

    @Test func monitorToggleEnablesAndPersists() async {
        let defaults = makeDefaults()
        let first = AppModel(defaults: defaults)
        await first.registry.setEnabled("monitor", true)
        #expect(first.registry.isEnabled("monitor"))
        #expect(first.registry.failures["monitor"] == nil)

        let second = AppModel(defaults: defaults)
        #expect(second.registry.isEnabled("monitor"))

        await first.registry.setEnabled("monitor", false)
        #expect(!first.registry.isEnabled("monitor"))
    }

    @Test func onboardingFlagPersists() {
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults)
        #expect(!model.onboardingCompleted)
        model.completeOnboarding()
        #expect(AppModel(defaults: defaults).onboardingCompleted)
    }
}
