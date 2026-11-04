@preconcurrency import AVFoundation
import Foundation
import ScreenCaptureKit

/// The file a recording is written to: in Movies, stamped with the time it started.
public func recordingFileName(now: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Sonary \(formatter.string(from: now)).mp4"
}

/// A bitrate that keeps a screen recording readable without filling the disk:
/// roughly 0.12 bits per pixel per frame, clamped to something sensible.
public func recordingBitrate(width: Int, height: Int, fps: Int = 30) -> Int {
    let raw = Double(width * height * fps) * 0.12
    return Int(min(max(raw, 2_000_000), 40_000_000))
}

/// Records a display to an MP4 with ScreenCaptureKit. Everything that touches the
/// writer happens on one serial queue, so frames never race the stop.
public final class ScreenRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.sonary.recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false

    public private(set) var outputURL: URL?

    public override init() { super.init() }

    /// Starts recording the main display. Throws when the permission is missing or
    /// the file cannot be created.
    public func start(to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.queueDepth = 6

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: display.width,
            AVVideoHeightKey: display.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: recordingBitrate(width: display.width, height: display.height),
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.cannotWrite }
        writer.add(input)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        queue.sync {
            self.writer = writer
            self.input = input
            self.stream = stream
            self.started = false
        }
        outputURL = url
    }

    /// Stops recording and returns the finished file, or nil when nothing was written.
    public func stop() async -> URL? {
        guard let stream else { return nil }
        try? await stream.stopCapture()
        let url = outputURL
        let writer = queue.sync { () -> AVAssetWriter? in
            self.input?.markAsFinished()
            let writer = self.writer
            self.stream = nil
            self.writer = nil
            self.input = nil
            self.started = false
            return writer
        }
        guard let writer, writer.status == .writing else { return nil }
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        outputURL = nil
        return url
    }

    public var isRecording: Bool { queue.sync { stream != nil } }

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, CMSampleBufferGetNumSamples(buffer) > 0,
              let writer, let input else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            started = true
        }
        guard input.isReadyForMoreMediaData else { return }
        input.append(buffer)
    }

    public enum RecorderError: Error { case noDisplay, cannotWrite }
}
