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
        guard format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let value = inputBar(rms: rootMeanSquare(samples))
            Task { @MainActor [weak self] in
                self?.level = value
                self?.onChange?(value)
            }
        }
        do { try engine.start() } catch { return }
        self.engine = engine
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }
}
