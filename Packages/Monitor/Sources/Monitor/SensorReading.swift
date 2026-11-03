public protocol SensorReading: Sendable {
    func gpuUsage() -> Double?
    func temperatures() -> [String: Double]
}

/// Used until a real sensor reader is available, and on machines where sensors cannot be read.
public struct NoSensors: SensorReading {
    public init() {}
    public func gpuUsage() -> Double? { nil }
    public func temperatures() -> [String: Double] { [:] }
}
