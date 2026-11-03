import Foundation
import Testing
@testable import Mouse

final class FakeControl: AccelerationControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double?
    private(set) var writes: [Double] = []

    init(value: Double?) { self.value = value }

    func read() -> Double? { lock.withLock { value } }
    func write(_ newValue: Double) -> Bool {
        lock.withLock {
            writes.append(newValue)
            value = newValue
            return true
        }
    }
}

struct PointerAccelerationTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sonary.accel.\(UUID().uuidString)")!
    }

    @Test func disableStoresOriginalAndWritesOff() {
        let control = FakeControl(value: 0.6875)
        let guardian = AccelerationGuard(control: control, defaults: makeDefaults())
        #expect(guardian.disable())
        #expect(control.read() == -1)
    }

    @Test func restoreWritesOriginalBack() {
        let control = FakeControl(value: 0.6875)
        let guardian = AccelerationGuard(control: control, defaults: makeDefaults())
        guardian.disable()
        guardian.restore()
        #expect(control.read() == 0.6875)
    }

    @Test func secondDisableKeepsFirstOriginal() {
        let control = FakeControl(value: 0.5)
        let guardian = AccelerationGuard(control: control, defaults: makeDefaults())
        guardian.disable()
        guardian.disable()
        guardian.restore()
        #expect(control.read() == 0.5)
    }

    @Test func recoverIfNeededRestoresAfterCrash() {
        let defaults = makeDefaults()
        let control = FakeControl(value: 0.75)
        AccelerationGuard(control: control, defaults: defaults).disable()
        // The app "crashes" here; a new guard is created on the next start.
        AccelerationGuard(control: control, defaults: defaults).recoverIfNeeded()
        #expect(control.read() == 0.75)
    }

    @Test func restoreWithoutDisableDoesNothing() {
        let control = FakeControl(value: 0.5)
        AccelerationGuard(control: control, defaults: makeDefaults()).restore()
        #expect(control.writes.isEmpty)
    }

    @Test func unreadableOriginalDoesNotWriteAndReturnsFalse() {
        let control = FakeControl(value: nil)
        let guardian = AccelerationGuard(control: control, defaults: makeDefaults())
        #expect(!guardian.disable())
        #expect(control.writes.isEmpty)
    }
}
