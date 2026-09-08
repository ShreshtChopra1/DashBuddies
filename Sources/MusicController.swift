import Foundation
import MediaPlayer
import UIKit

/// Controls Apple Music / the system Music app via the MediaPlayer framework.
///
/// iOS does **not** let a third-party app control other players (Spotify,
/// YouTube Music, etc.) — each service needs its own SDK + login — so this drives
/// `MPMusicPlayerController.systemMusicPlayer` only. Spotify support can be added
/// later as a separate backend behind the same play/pause/skip surface.
final class MusicController: ObservableObject {
    @Published var title = "Nothing playing"
    @Published var subtitle = "Open Apple Music to start"
    @Published var artwork: UIImage?
    @Published var isPlaying = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observing = false

    /// Request access, then start watching the system player. Safe to call again.
    func begin() {
        MPMediaLibrary.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.startObserving() }
        }
    }

    func end() {
        guard observing else { return }
        observing = false
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    func playPause() { isPlaying ? player.pause() : player.play() }
    func next()      { player.skipToNextItem() }
    func previous()  { player.skipToPreviousItem() }

    private func startObserving() {
        guard !observing else { refresh(); return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh),
                       name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
        nc.addObserver(self, selector: #selector(refresh),
                       name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
        player.beginGeneratingPlaybackNotifications()
        refresh()
    }

    @objc private func refresh() {
        let item = player.nowPlayingItem
        title = item?.title ?? "Nothing playing"
        subtitle = item?.artist ?? "Open Apple Music to start"
        artwork = item?.artwork?.image(at: CGSize(width: 160, height: 160))
        isPlaying = player.playbackState == .playing
    }

    deinit { end() }
}
