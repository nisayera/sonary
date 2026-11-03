import Foundation

public enum MusicPlayer: String, CaseIterable, Sendable {
    case music
    case spotify

    public var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    public var notificationName: String {
        switch self {
        case .music: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    /// The name AppleScript uses for the app.
    public var scriptName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var player: MusicPlayer

    public init(title: String, artist: String, album: String, isPlaying: Bool, player: MusicPlayer) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.player = player
    }
}

/// Reads the user info of the players' distributed notifications. Stopped or untitled → nil.
public func parseNowPlaying(_ info: [String: Any], player: MusicPlayer) -> NowPlaying? {
    let state = info["Player State"] as? String
    guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else { return nil }
    return NowPlaying(
        title: title,
        artist: info["Artist"] as? String ?? "",
        album: info["Album"] as? String ?? "",
        isPlaying: state == "Playing",
        player: player
    )
}
