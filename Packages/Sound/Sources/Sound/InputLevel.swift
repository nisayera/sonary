@preconcurrency import AVFoundation
import Foundation

/// A loudness reading as a bar from 0 to 1. Silence sits at the bottom rather than at
/// minus infinity, and anything above the top of the scale is clamped.
public func inputBar(rms: Float, floor: Double = -60) -> Double {
    guard rms > 0, floor < 0 else { return 0 }
    let decibels = 20 * log10(Double(rms))
    return min(max((decibels - floor) / -floor, 0), 1)
}

/// The root mean square of one buffer of samples.
public func rootMeanSquare(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let total = samples.reduce(Float(0)) { $0 + $1 * $1 }
    return (total / Float(samples.count)).squareRoot()
}

/// Watches the microphone's loudness. The engine is only running while something is
/// looking at the meter, so Sonary does not hold the microphone open all day.
@MainActor
final class InputLevelReader {
    private var engine: AVAudioEngine?
    private(set) var level: Double = 0
    var onChange: ((Double) -> Void)?

    func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        let tap = Self.levelTap { [weak self] value in
            Task { @MainActor [weak self] in
                self?.level = value
                self?.onChange?(value)
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        self.engine = engine
    }

    /// The block Core Audio calls with each buffer, on its own audio thread. It is made
    /// here, outside the main actor, on purpose: a block written inside `start()` would
    /// belong to the main actor, Swift checks that when it runs, and the app stopped the
    /// moment the first buffer arrived.
    nonisolated private static func levelTap(_ report: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            report(inputBar(rms: rootMeanSquare(samples)))
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }
}
