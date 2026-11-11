import Foundation
import Synchronization

/// What running an AppleScript gave back.
public enum AppleScriptOutcome: Equatable, Sendable {
    /// The script ran; carries its result as text, when it returned any.
    case success(String?)
    /// The script failed, for example because Automation permission is missing.
    case failed(String)
    /// The script did not answer in time, for example because the app it talks to hangs.
    case timedOut

    public var succeeded: Bool {
        if case .success = self { return true }
        return false
    }

    /// The text result of a script that ran, nil otherwise.
    public var text: String? {
        if case .success(let text) = self { return text }
        return nil
    }
}

/// Runs AppleScript off the main thread, with a time limit.
///
/// `NSAppleScript.executeAndReturnError` blocks until the target app answers. Run on the main
/// thread, a hanging Music, Spotify or Finder froze the panel and the notch with it (an Apple
/// event waits up to two minutes by default). Scripts here run one at a time on a background
/// queue, each inside `with timeout`, and the caller stops waiting after the same limit even if
/// the script itself never returns.
public enum AppleScriptRunner {
    public static let defaultTimeout = 5

    /// One serial queue: NSAppleScript is not meant to be used from several threads at once.
    private static let queue = DispatchQueue(label: "app.sonary.applescript", qos: .userInitiated)

    /// The script inside a `with timeout` block, so Apple events to a hanging app give up.
    public static func wrapped(_ source: String, timeout seconds: Int) -> String {
        "with timeout of \(max(1, seconds)) seconds\n\(source)\nend timeout"
    }

    public static func run(_ source: String, timeout seconds: Int = defaultTimeout) async -> AppleScriptOutcome {
        let script = wrapped(source, timeout: seconds)
        return await withCheckedContinuation { (continuation: CheckedContinuation<AppleScriptOutcome, Never>) in
            let once = ResumeOnce(continuation)
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
                if let error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    once.resume(.failed(message))
                } else {
                    once.resume(.success(result?.stringValue))
                }
            }
            // A second's grace over the script's own limit, so its timeout error wins when it fires.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(max(1, seconds) + 1)) {
                once.resume(.timedOut)
            }
        }
    }

    /// Runs a script without waiting for it, for fire-and-forget commands such as "playpause".
    public static func launch(_ source: String, timeout seconds: Int = defaultTimeout) {
        Task.detached(priority: .userInitiated) { _ = await AppleScriptRunner.run(source, timeout: seconds) }
    }
}

/// Resumes a continuation exactly once, whichever of the script and the timer comes first.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<AppleScriptOutcome, Never>?>

    init(_ continuation: CheckedContinuation<AppleScriptOutcome, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ outcome: AppleScriptOutcome) {
        let pending = continuation.withLock { value in
            let current = value
            value = nil
            return current
        }
        pending?.resume(returning: outcome)
    }
}
