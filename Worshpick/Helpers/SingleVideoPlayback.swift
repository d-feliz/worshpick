import AVFoundation

/// The library panel and the song sheet each own a player; this keeps only the newest one playing.
@MainActor
final class SingleVideoPlayback {
    private weak var newestPlayer: AVPlayer?

    func makePlayer(for videoURL: URL) -> AVPlayer {
        newestPlayer?.pause()
        let player = AVPlayer(url: videoURL)
        newestPlayer = player
        return player
    }

    /// SwiftUI's VideoPlayer can keep a replaced AVPlayer alive and playing, so the old one is emptied explicitly.
    func discard(_ player: AVPlayer?) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
}
