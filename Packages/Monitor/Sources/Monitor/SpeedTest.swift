import Foundation

public struct SpeedTestResult: Equatable, Sendable {
    public var downloadBitsPerSecond: Double
    public var latency: TimeInterval

    public init(downloadBitsPerSecond: Double, latency: TimeInterval) {
        self.downloadBitsPerSecond = downloadBitsPerSecond
        self.latency = latency
    }
}

/// Bits per second from the bytes that arrived in a measured span. A span of zero
/// means the measurement is worthless, so it reports nothing rather than infinity.
public func throughput(bytes: Int, seconds: TimeInterval) -> Double? {
    guard seconds > 0.01, bytes > 0 else { return nil }
    return Double(bytes) * 8 / seconds
}

/// Reads a throughput as the user sees it: Mbit/s with one decimal, Gbit/s when it is huge.
public func formatThroughput(_ bitsPerSecond: Double) -> String {
    let mbit = bitsPerSecond / 1_000_000
    if mbit >= 1000 {
        return String(format: "%.2f Gbit/s", mbit / 1000)
    }
    return String(format: "%.1f Mbit/s", mbit)
}

public func formatLatency(_ seconds: TimeInterval) -> String {
    String(format: "%.0f ms", seconds * 1000)
}

/// Downloads a known-size file and times it. Cloudflare's endpoint is used because it
/// needs no key and serves exactly the number of bytes asked for.
public func runSpeedTest(bytes: Int = 25_000_000,
                         session: URLSession = .shared) async throws -> SpeedTestResult {
    guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else {
        throw SpeedTestError.badEndpoint
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.timeoutInterval = 30

    let started = Date()
    let (data, response) = try await session.data(for: request)
    let elapsed = Date().timeIntervalSince(started)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          let rate = throughput(bytes: data.count, seconds: elapsed) else {
        throw SpeedTestError.noUsableMeasurement
    }
    return SpeedTestResult(downloadBitsPerSecond: rate, latency: try await latency(session: session))
}

/// A small request, timed, as a stand-in for a ping.
private func latency(session: URLSession) async throws -> TimeInterval {
    guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1") else {
        throw SpeedTestError.badEndpoint
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.timeoutInterval = 10
    var best = TimeInterval.greatestFiniteMagnitude
    for _ in 0..<3 {
        let started = Date()
        _ = try? await session.data(for: request)
        best = min(best, Date().timeIntervalSince(started))
    }
    return best == .greatestFiniteMagnitude ? 0 : best
}

public enum SpeedTestError: Error { case badEndpoint, noUsableMeasurement }
