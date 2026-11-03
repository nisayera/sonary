public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    /// Oldest element first.
    public var elements: [Element] { storage }
}
