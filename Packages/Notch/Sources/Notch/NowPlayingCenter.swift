import AppKit
import Observation
import SonaryCore

/// Follows Music and Spotify through their distributed notifications and controls them with AppleScript.
@MainActor
@Observable
public final class NowPlayingCenter {
    public private(set) var nowPlaying: NowPlaying?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init() {}

    public func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            let token = center.addObserver(forName: Notification.Name(player.notificationName), object: nil, queue: .main) {
                [weak self] note in
                let info = (note.userInfo as? [String: Any]) ?? [:]
                let parsed = parseNowPlaying(info, player: player)
                MainActor.assumeIsolated { self?.receive(parsed, from: player) }
            }
            observers.append(token)
        }
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
        nowPlaying = nil
    }

    private func receive(_ parsed: NowPlaying?, from player: MusicPlayer) {
        if let parsed {
            nowPlaying = parsed
        } else if nowPlaying?.player == player {
            nowPlaying = nil
        }
    }

    public func playPause() { send("playpause") }
    public func next() { send("next track") }
    public func previous() { send("previous track") }

    /// Only talks to a player that is already running, so a click never launches an app.
    private func send(_ command: String) {
        guard let player = nowPlaying?.player,
              !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else { return }
        // In the background with a time limit: a hanging player must not freeze the notch.
        AppleScriptRunner.launch("tell application \"\(player.scriptName)\" to \(command)")
    }
}
