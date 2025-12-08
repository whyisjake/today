//
//  PodcastAudioPlayer.swift
//  Today
//
//  Audio player for playing podcast/audio enclosures from RSS feeds
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import SwiftData

@MainActor
class PodcastAudioPlayer: NSObject, ObservableObject {
    static let shared = PodcastAudioPlayer()

    private var player: AVPlayer?
    private var timeObserver: Any?
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentArticle: Article?
    @Published var progress: Double = 0.0 // 0.0 to 1.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var playbackRate: Float = 1.0

    // Cache artwork to avoid reloading on every Now Playing update
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkArticleId: PersistentIdentifier?

    override private init() {
        super.init()
        setupRemoteCommandCenter()
        setupAudioSession()
    }

    // MARK: - Audio Session Configuration

    private func setupAudioSession() {
        do {
            // Use .playback category for audio playback (allows background playback)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Playback Control

    func play(article: Article) {
        guard let audioUrlString = article.audioUrl,
              let audioUrl = URL(string: audioUrlString) else {
            print("No audio URL found for article")
            return
        }

        // Stop current playback if switching articles
        if currentArticle?.id != article.id {
            stop()
        }

        currentArticle = article
        
        // Create player if needed
        if player == nil {
            let playerItem = AVPlayerItem(url: audioUrl)
            player = AVPlayer(playerItem: playerItem)
            setupPlayerObservers()
        }

        // Start playback
        player?.play()
        player?.rate = playbackRate
        isPlaying = true
        isPaused = false

        updateNowPlayingInfo()
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPaused = true
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard isPaused else { return }
        player?.play()
        player?.rate = playbackRate
        isPaused = false
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        player?.pause()
        player = nil
        removePlayerObservers()
        
        isPlaying = false
        isPaused = false
        progress = 0.0
        currentTime = 0.0
        duration = 0.0
        currentArticle = nil
        
        clearNowPlayingInfo()
        
        // Clear artwork cache
        cachedArtwork = nil
        cachedArtworkArticleId = nil
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else if let article = currentArticle {
            play(article: article)
        }
    }

    // MARK: - Seeking Control

    func seek(to newProgress: Double) {
        guard let player = player, duration > 0 else { return }
        
        let targetTime = duration * newProgress
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        
        player.seek(to: cmTime) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    // MARK: - Playback Rate Control

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        
        // Apply rate immediately if playing or paused
        if isPlaying || isPaused {
            player?.rate = isPlaying ? playbackRate : 0.0
            updateNowPlayingInfo()
        }
    }

    // MARK: - Player Observers

    private func setupPlayerObservers() {
        guard let player = player else { return }

        // Observe playback time
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            self.currentTime = time.seconds
            
            if let duration = self.player?.currentItem?.duration.seconds,
               duration.isFinite,
               duration > 0 {
                self.duration = duration
                self.progress = self.currentTime / duration
            }
            
            self.updateNowPlayingInfo()
        }

        // Observe when playback ends
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    private func removePlayerObservers() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    @objc private func playerDidFinishPlaying() {
        Task { @MainActor in
            isPlaying = false
            isPaused = false
            progress = 1.0
            updateNowPlayingInfo()
        }
    }

    // MARK: - Now Playing Info (Lock Screen)

    private func updateNowPlayingInfo() {
        guard let article = currentArticle else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: article.title,
            MPMediaItemPropertyArtist: article.feed?.title ?? "Today RSS Reader",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPMediaItemPropertyPlaybackDuration: duration
        ]

        // Check if we have cached artwork for this article
        if let cachedArtwork = cachedArtwork, cachedArtworkArticleId == article.id {
            // Use cached artwork
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
        } else {
            // Need to load artwork for this article

            // Start loading article thumbnail asynchronously (only if we don't have it cached)
            if cachedArtworkArticleId != article.id,
               let imageUrlString = article.imageUrl,
               let imageUrl = URL(string: imageUrlString) {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: imageUrl)
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                // Only cache and update if still playing the same article
                                guard self.currentArticle?.id == article.id else { return }
                                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                                self.cachedArtwork = artwork
                                self.cachedArtworkArticleId = article.id

                                // Update Now Playing with the loaded artwork
                                var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                                updatedInfo[MPMediaItemPropertyArtwork] = artwork
                                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                            }
                        }
                    } catch {
                        // Failed to load thumbnail, will use app icon fallback
                    }
                }
            }

            // Use SF Symbol as fallback artwork (immediate)
            let fallbackImage = createFallbackArtwork()
            let fallbackArtwork = MPMediaItemArtwork(boundsSize: fallbackImage.size) { _ in fallbackImage }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = fallbackArtwork

            // Cache the fallback if we don't have a thumbnail URL
            if article.imageUrl == nil {
                cachedArtwork = fallbackArtwork
                cachedArtworkArticleId = article.id
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Creates a fallback artwork image using SF Symbols
    private func createFallbackArtwork() -> UIImage {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Background
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Waveform icon
            let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .medium)
            if let symbol = UIImage(systemName: "waveform", withConfiguration: config) {
                let symbolSize = symbol.size
                let x = (size.width - symbolSize.width) / 2
                let y = (size.height - symbolSize.height) / 2
                symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(at: CGPoint(x: x, y: y))
            }
        }
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote Command Center (Lock Screen Controls)

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }

        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // Skip forward/backward commands
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            
            let newTime = self.currentTime + skipEvent.interval
            let newProgress = newTime / self.duration
            self.seek(to: min(1.0, max(0.0, newProgress)))
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            
            let newTime = self.currentTime - skipEvent.interval
            let newProgress = newTime / self.duration
            self.seek(to: min(1.0, max(0.0, newProgress)))
            return .success
        }
    }
}
