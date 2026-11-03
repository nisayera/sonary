import Foundation

/// Small lock-protected box for state shared between the event-tap thread and the main thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Carries a non-Sendable system object across a thread boundary where its use is known to be safe.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}
