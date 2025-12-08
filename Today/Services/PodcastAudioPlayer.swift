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

// MARK: - Chapter Model

struct PodcastChapter: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let imageUrl: String?
    let url: String?  // Link associated with chapter

    var formattedStartTime: String {
        AudioFormatters.formatDuration(startTime)
    }
}

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
    @Published var chapters: [PodcastChapter] = []
    @Published var currentChapter: PodcastChapter?

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

            // Extract chapters from the audio file
            Task {
                await extractChapters(from: playerItem.asset)
            }
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
        chapters = []
        currentChapter = nil

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

    /// Seek to a specific chapter
    func seekToChapter(_ chapter: PodcastChapter) {
        guard duration > 0 else { return }
        let newProgress = chapter.startTime / duration
        seek(to: newProgress)
    }

    /// Skip to the next chapter
    func nextChapter() {
        guard let current = currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }),
              currentIndex + 1 < chapters.count else { return }
        seekToChapter(chapters[currentIndex + 1])
    }

    /// Skip to the previous chapter (or restart current if > 3 seconds in)
    func previousChapter() {
        guard let current = currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }) else { return }

        // If more than 3 seconds into chapter, restart it
        if currentTime - current.startTime > 3 {
            seekToChapter(current)
        } else if currentIndex > 0 {
            seekToChapter(chapters[currentIndex - 1])
        } else {
            seekToChapter(current) // Restart first chapter
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

            // Update current chapter based on playback time
            self.updateCurrentChapter()

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

    // MARK: - Chapter Extraction

    /// Update the current chapter based on playback time
    private func updateCurrentChapter() {
        guard !chapters.isEmpty else { return }

        // Find the chapter that contains the current time
        let newChapter = chapters.last { chapter in
            currentTime >= chapter.startTime
        }

        if newChapter?.id != currentChapter?.id {
            currentChapter = newChapter
        }
    }

    /// Extract chapters from the audio asset using AVFoundation
    /// This works for M4A/AAC files with chapter markers and some MP3s with ID3 chapters
    private func extractChapters(from asset: AVAsset) async {
        do {
            // Try to load chapter metadata groups
            let languages = try await asset.load(.availableChapterLocales).map { $0.identifier }
            let preferredLanguages = languages.isEmpty ? [Locale.current.identifier] : languages

            let chapterGroups = try await asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: preferredLanguages
            )

            guard !chapterGroups.isEmpty else {
                print("📖 No chapters found in audio file")
                // Try ID3 metadata extraction as fallback
                await extractID3Chapters(from: asset)
                return
            }

            var extractedChapters: [PodcastChapter] = []

            for (index, group) in chapterGroups.enumerated() {
                let startTime = group.timeRange.start.seconds
                let endTime = (group.timeRange.start + group.timeRange.duration).seconds

                // Extract chapter title
                var title = "Chapter \(index + 1)"
                var imageUrl: String? = nil

                for item in group.items {
                    if let commonKey = item.commonKey {
                        switch commonKey {
                        case .commonKeyTitle:
                            if let stringValue = try? await item.load(.stringValue) {
                                title = stringValue
                            }
                        case .commonKeyArtwork:
                            // Chapter-specific artwork (we could extract this)
                            break
                        default:
                            break
                        }
                    }
                }

                extractedChapters.append(PodcastChapter(
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    imageUrl: imageUrl,
                    url: nil
                ))
            }

            await MainActor.run {
                self.chapters = extractedChapters.sorted { $0.startTime < $1.startTime }
                print("📖 Extracted \(self.chapters.count) chapters from AVFoundation")
                for chapter in self.chapters {
                    print("   - \(chapter.formattedStartTime): \(chapter.title)")
                }
            }
        } catch {
            print("📖 Failed to extract chapters: \(error)")
            // Try ID3 fallback
            await extractID3Chapters(from: asset)
        }
    }

    /// Extract chapters from ID3 metadata (MP3 files)
    /// Note: AVFoundation has limited ID3 CHAP support - for full support,
    /// consider adding a library like OutcastID3 or SwiftTaggerID3
    private func extractID3Chapters(from asset: AVAsset) async {
        do {
            let metadata = try await asset.load(.metadata)

            // Look for ID3 chapter markers in common metadata
            var chapterItems: [(title: String, time: TimeInterval)] = []

            for item in metadata {
                // Check for chapter-related keys
                if let key = item.key as? String {
                    print("📖 ID3 key: \(key)")
                }

                // ID3 CHAP frames would appear here, but AVFoundation's support is limited
                // For full MP3 chapter support, you'd need a dedicated ID3 library
            }

            if !chapterItems.isEmpty {
                await MainActor.run {
                    self.chapters = chapterItems.map { item in
                        PodcastChapter(
                            title: item.title,
                            startTime: item.time,
                            endTime: nil,
                            imageUrl: nil,
                            url: nil
                        )
                    }.sorted { $0.startTime < $1.startTime }
                    print("📖 Extracted \(self.chapters.count) chapters from ID3 metadata")
                }
            } else {
                print("📖 No ID3 chapters found. For full MP3 chapter support, consider adding OutcastID3 or SwiftTaggerID3 library.")
            }
        } catch {
            print("📖 Failed to load ID3 metadata: \(error)")
        }
    }
}
