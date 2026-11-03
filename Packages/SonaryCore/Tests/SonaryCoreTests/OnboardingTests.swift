import Foundation
import Testing
@testable import SonaryCore

final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    var shouldThrow = false

    var isEnabled: Bool { lock.withLock { enabled } }

    func setEnabled(_ on: Bool) throws {
        if shouldThrow { throw Boom() }
        lock.withLock { enabled = on }
    }
}

@MainActor
struct OnboardingTests {
    @Test func stepsDedupePermissionsAcrossModules() {
        let a = FakeModule(id: "a", permissions: [.accessibility, .notifications])
        let b = FakeModule(id: "b", permissions: [.accessibility])
        let steps = onboardingSteps(for: [a, b])
        #expect(steps == [
            OnboardingStep(permission: .accessibility, moduleIDs: ["a", "b"]),
            OnboardingStep(permission: .notifications, moduleIDs: ["a"]),
        ])
    }

    @Test func stepsEmptyWhenNoModuleNeedsPermissions() {
        #expect(onboardingSteps(for: [FakeModule(id: "a")]).isEmpty)
    }

    @Test func launchAtLoginPropagatesErrorFromController() {
        let item = FakeLoginItem()
        let model = LaunchAtLoginModel(controller: item)
        item.shouldThrow = true
        model.set(true)
        #expect(model.errorMessage == "boom")
        #expect(model.isEnabled == false)
    }

    @Test func launchAtLoginReflectsControllerState() {
        let model = LaunchAtLoginModel(controller: FakeLoginItem())
        model.set(true)
        #expect(model.isEnabled)
        #expect(model.errorMessage == nil)
    }
}
