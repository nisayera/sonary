import Foundation
import Testing
@testable import SonaryCore

@MainActor
struct ModuleRegistryTests {
    @Test func enabledStatePersistsInDefaults() async {
        let defaults = makeDefaults()
        let module = FakeModule(id: "a")
        let first = ModuleRegistry(modules: [module], defaults: defaults, permissions: FakeGate(result: true))
        await first.setEnabled("a", true)

        let second = ModuleRegistry(modules: [FakeModule(id: "a")], defaults: defaults, permissions: FakeGate(result: true))
        #expect(second.isEnabled("a"))
    }

    @Test func startEnabledStartsOnlyEnabledModules() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "module.a.enabled")
        let a = FakeModule(id: "a")
        let b = FakeModule(id: "b")
        let registry = ModuleRegistry(modules: [a, b], defaults: defaults, permissions: FakeGate(result: true))
        await registry.startEnabled()
        #expect(a.startCount == 1)
        #expect(b.startCount == 0)
    }

    @Test func setEnabledFalseCallsStopOnce() async {
        let module = FakeModule(id: "a")
        let registry = ModuleRegistry(modules: [module], defaults: makeDefaults(), permissions: FakeGate(result: true))
        await registry.setEnabled("a", true)
        await registry.setEnabled("a", false)
        await registry.setEnabled("a", false)
        #expect(module.stopCount == 1)
        #expect(!registry.isEnabled("a"))
    }

    @Test func throwingStartDisablesModuleAndRecordsFailure() async {
        let bad = FakeModule(id: "bad", startError: Boom())
        let good = FakeModule(id: "good")
        let defaults = makeDefaults()
        defaults.set(true, forKey: "module.bad.enabled")
        defaults.set(true, forKey: "module.good.enabled")
        let registry = ModuleRegistry(modules: [bad, good], defaults: defaults, permissions: FakeGate(result: true))
        await registry.startEnabled()

        #expect(!registry.isEnabled("bad"))
        #expect(registry.failures["bad"] == "boom")
        #expect(registry.isEnabled("good"))
        #expect(good.startCount == 1)
        #expect(defaults.bool(forKey: "module.bad.enabled") == false)
    }

    @Test func deniedPermissionKeepsModuleOff() async {
        let module = FakeModule(id: "a", permissions: [.accessibility])
        let registry = ModuleRegistry(modules: [module], defaults: makeDefaults(), permissions: FakeGate(result: false))
        await registry.setEnabled("a", true)
        #expect(!registry.isEnabled("a"))
        #expect(module.startCount == 0)
        #expect(registry.failures["a"] != nil)
    }
}
