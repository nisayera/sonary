import Foundation

public struct FanReading: Equatable, Sendable, Identifiable {
    public var index: Int
    public var rpm: Double
    public var minimum: Double?
    public var maximum: Double?
    public var id: Int { index }

    public init(index: Int, rpm: Double, minimum: Double? = nil, maximum: Double? = nil) {
        self.index = index
        self.rpm = rpm
        self.minimum = minimum
        self.maximum = maximum
    }

    /// How hard the fan is working, 0 at its slowest and 1 at its fastest. Nil without both ends.
    public var load: Double? {
        guard let minimum, let maximum, maximum > minimum else { return nil }
        return min(max((rpm - minimum) / (maximum - minimum), 0), 1)
    }
}

/// Throws out readings the SMC reports for fans that are not there: a Mac with no fan at all
/// still answers, with zeros or nonsense.
public func plausibleFans(_ readings: [FanReading]) -> [FanReading] {
    readings.filter { $0.rpm > 0 && $0.rpm < 20_000 }
}

/// "2 400 rpm" with a thin space, or "—" when nothing is spinning.
public func formatFanSpeed(_ readings: [FanReading]) -> String {
    guard let fastest = readings.map(\.rpm).max(), fastest > 0 else { return "—" }
    return "\(Int(fastest.rounded())) rpm"
}

public protocol FanSource: Sendable {
    func fans() -> [FanReading]
}

public struct NoFans: FanSource {
    public init() {}
    public func fans() -> [FanReading] { [] }
}

/// Reads the fan keys the SMC offers: FNum says how many there are, then F0Ac, F1Ac and so on
/// give the current speed, with F0Mn and F0Mx for the ends of the range.
public struct SMCFanReader: FanSource {
    public init() {}

    public func fans() -> [FanReading] {
        guard let client = SMCClient() else { return [] }
        guard let countKey = client.key(named: "FNum"), let count = client.readValue(countKey), count > 0 else { return [] }
        return plausibleFans((0..<Int(count)).compactMap { index in
            guard let speedKey = client.key(named: "F\(index)Ac"), let rpm = client.readValue(speedKey) else { return nil }
            let minimum = client.key(named: "F\(index)Mn").flatMap { client.readValue($0) }
            let maximum = client.key(named: "F\(index)Mx").flatMap { client.readValue($0) }
            return FanReading(index: index, rpm: rpm, minimum: minimum, maximum: maximum)
        })
    }
}
