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

/// A part of one display to record, in that display's points with the origin top left.
public struct RecordingRegion: Equatable, Sendable {
    public var displayID: UInt32
    public var rect: CGRect
    /// Pixels per point, so the file has the display's sharpness.
    public var scale: CGFloat

    public init(displayID: UInt32, rect: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
    }

    /// The size of the video, in even pixels as the encoder wants them.
    public var pixelSize: (width: Int, height: Int) {
        (Int((rect.width * scale / 2).rounded()) * 2, Int((rect.height * scale / 2).rounded()) * 2)
    }
}

/// A region in screen coordinates (origin bottom left of the main display) turned into one
/// within its display, with the origin at the display's top left.
public func recordingSourceRect(_ rect: CGRect, screenFrame: CGRect) -> CGRect {
    CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
}

/// Records a display, or part of one, to an MP4 with ScreenCaptureKit's own file output,
/// which also takes the sound the Mac plays and the microphone when asked.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var finished: CheckedContinuation<Void, Never>?
    /// Set once the file output says it is done, which can come before anyone waits for it.
    private var didFinish = false
    private var failed = false
    private let queue = DispatchQueue(label: "app.sonary.recorder")

    public private(set) var outputURL: URL?

    public override init() { super.init() }

    /// Starts recording the main display, or a region of one. Throws when the permission is
    /// missing or the file cannot be created.
    public func start(to url: URL, region: RecordingRegion? = nil, systemAudio: Bool = false,
                      microphone: Bool = false) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = region.flatMap { region in content.displays.first { $0.displayID == region.displayID } }
            ?? content.displays.first
        guard let display else { throw RecorderError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        if let region, region.displayID == display.displayID {
            configuration.sourceRect = region.rect
            let size = region.pixelSize
            configuration.width = size.width
            configuration.height = size.height
        } else {
            configuration.width = display.width
            configuration.height = display.height
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.capturesAudio = systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = microphone

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recording, delegate: self)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        // The file output does the writing; the screen output only keeps the stream fed.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        lock.withLock {
            self.stream = stream
            self.output = output
            self.failed = false
            self.didFinish = false
        }
        outputURL = url
    }

    /// Stops recording and returns the finished file, or nil when nothing was written.
    public func stop() async -> URL? {
        guard let stream = lock.withLock({ self.stream }) else { return nil }
        if (try? await stream.stopCapture()) != nil {
            // The file is complete once the output says so; never wait on it for ever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.resumeFinished()
            }
            await withCheckedContinuation { continuation in
                let done = lock.withLock { () -> Bool in
                    if didFinish { return true }
                    finished = continuation
                    return false
                }
                if done { continuation.resume() }
            }
        }
        let url = outputURL
        let failed = lock.withLock { () -> Bool in
            self.stream = nil
            self.output = nil
            return self.failed
        }
        outputURL = nil
        guard !failed, let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public var isRecording: Bool { lock.withLock { stream != nil } }

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resumeFinished()
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        lock.withLock { failed = true }
        resumeFinished()
    }

    private func resumeFinished() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            didFinish = true
            let continuation = finished
            finished = nil
            return continuation
        }
        continuation?.resume()
    }

    public enum RecorderError: Error { case noDisplay, cannotWrite }
}
