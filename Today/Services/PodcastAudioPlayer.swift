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
    let image: UIImage?  // Chapter artwork (from ID3 tags)

    var formattedStartTime: String {
        AudioFormatters.formatDuration(startTime)
    }

    // Equatable conformance (UIImage doesn't conform by default)
    static func == (lhs: PodcastChapter, rhs: PodcastChapter) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.imageUrl == rhs.imageUrl &&
        lhs.url == rhs.url
    }

    init(title: String, startTime: TimeInterval, endTime: TimeInterval?, imageUrl: String?, url: String?, image: UIImage? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.imageUrl = imageUrl
        self.url = url
        self.image = image
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

    // Playback position storage
    private let playbackPositionsKey = "PodcastPlaybackPositions"
    private var lastSavedTime: TimeInterval = 0
    private let saveInterval: TimeInterval = 5 // Save every 5 seconds of playback
    private var isRestoringPosition = false // Flag to prevent saving during restore

    // Playback speed persistence
    private let playbackRateKey = "PodcastPlaybackRate"

    // Chapter prefetch cache (keyed by audio URL)
    private var prefetchedChapters: [String: [PodcastChapter]] = [:]
    private var prefetchingURLs: Set<String> = []

    override private init() {
        super.init()

        // Restore saved playback rate
        let savedRate = UserDefaults.standard.float(forKey: playbackRateKey)
        if savedRate > 0 {
            playbackRate = savedRate
        }

        setupRemoteCommandCenter()
        setupAudioSession()
        setupAppLifecycleObservers()
    }

    private func setupAppLifecycleObservers() {
        // Save playback position when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.savePlaybackPosition()
            }
        }

        // Save playback position when app is about to terminate
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.savePlaybackPosition()
            }
        }
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

    // MARK: - AI Chapters Support

    @Published var aiChapters: [AIChapterData] = []

    /// Load AI-generated chapters from download if available
    func loadAIChapters(for article: Article) {
        if let download = article.podcastDownload,
           let chapters = download.aiChapters {
            aiChapters = chapters
        } else {
            aiChapters = []
        }
    }

    /// Seek to an AI-generated chapter
    func seekToAIChapter(_ chapter: AIChapterData) {
        guard duration > 0 else { return }
        let progress = chapter.startTime / duration
        seek(to: progress)
    }

    // MARK: - Playback Control

    func play(article: Article) {
        guard let audioUrlString = article.audioUrl else {
            print("No audio URL found for article")
            return
        }

        // Determine playback URL - prefer local download if available
        let playbackURL: URL
        if let download = article.podcastDownload,
           download.downloadStatus == .completed,
           let localURL = PodcastDownloadManager.shared.getLocalFileURL(for: download) {
            playbackURL = localURL
            print("Playing from local file: \(localURL.lastPathComponent)")
        } else if let remoteURL = URL(string: audioUrlString) {
            playbackURL = remoteURL
            print("Streaming from remote URL")
        } else {
            print("Invalid audio URL")
            return
        }

        // Stop current playback if switching articles
        if currentArticle?.id != article.id {
            stop()
        }

        currentArticle = article

        // Load AI chapters if available
        loadAIChapters(for: article)

        // Create player if needed
        if player == nil {
            let playerItem = AVPlayerItem(url: playbackURL)
            player = AVPlayer(playerItem: playerItem)
            setupPlayerObservers()

            // Use prefetched chapters if available, otherwise extract
            Task {
                await usePrefetchedOrExtractChapters(from: playerItem.asset)
            }
        }

        // Start playback
        player?.play()
        player?.rate = playbackRate
        isPlaying = true
        isPaused = false

        // Restore saved playback position if available
        restorePlaybackPosition()

        updateNowPlayingInfo()
    }

    func pause() {
        savePlaybackPosition()
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
        // Save position before stopping (unless at the end)
        savePlaybackPosition()

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
        aiChapters = []
        lastSavedTime = 0
        isRestoringPosition = false

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
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.updateNowPlayingInfo()
            }
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

        // Persist the playback rate
        UserDefaults.standard.set(playbackRate, forKey: playbackRateKey)

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
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.currentTime = time.seconds

                if let duration = strongSelf.player?.currentItem?.duration.seconds,
                   duration.isFinite,
                   duration > 0 {
                    strongSelf.duration = duration
                    strongSelf.progress = strongSelf.currentTime / duration
                }

                // Update current chapter based on playback time
                strongSelf.updateCurrentChapter()

                // Periodically save playback position (every saveInterval seconds)
                if abs(strongSelf.currentTime - strongSelf.lastSavedTime) >= strongSelf.saveInterval {
                    strongSelf.savePlaybackPosition()
                }

                strongSelf.updateNowPlayingInfo()
            }
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
            // Clear saved position since episode is complete
            if let audioUrl = currentArticle?.audioUrl {
                clearPlaybackPosition(for: audioUrl)
            }

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

        // Priority for artwork:
        // 1. Current chapter artwork (if available)
        // 2. Cached article artwork
        // 3. Load article artwork from URL
        // 4. Fallback placeholder

        // Check if current chapter has artwork
        if let chapterImage = currentChapter?.image {
            let artwork = MPMediaItemArtwork(boundsSize: chapterImage.size) { _ in chapterImage }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        // Check if we have cached artwork for this article (and no chapter artwork)
        else if let cachedArtwork = cachedArtwork, cachedArtworkArticleId == article.id {
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

                                // Update Now Playing with the loaded artwork (only if no chapter artwork)
                                if self.currentChapter?.image == nil {
                                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                                    updatedInfo[MPMediaItemPropertyArtwork] = artwork
                                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                                }
                            }
                        }
                    } catch {
                        // Failed to load thumbnail, fallback artwork is already in use
                        print("⚠️ Failed to load podcast artwork: \(error.localizedDescription)")
                    }
                }
            }

            // Use app icon as fallback artwork (immediate)
            if let image = UIImage(named: "AppIcon") {
                let fallbackArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = fallbackArtwork

                // Cache the fallback if we don't have a thumbnail URL
                if article.imageUrl == nil {
                    cachedArtwork = fallbackArtwork
                    cachedArtworkArticleId = article.id
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

    // MARK: - Playback Position Storage

    /// Save the current playback position for resume functionality
    private func savePlaybackPosition() {
        // Don't save while we're restoring a position (prevents overwriting)
        guard !isRestoringPosition else { return }

        guard let audioUrl = currentArticle?.audioUrl,
              currentTime > 0,
              duration > 0 else { return }

        // Don't save if we're at the end (within last 30 seconds)
        if duration - currentTime < 30 {
            clearPlaybackPosition(for: audioUrl)
            return
        }

        var positions = UserDefaults.standard.dictionary(forKey: playbackPositionsKey) as? [String: Double] ?? [:]
        positions[audioUrl] = currentTime
        UserDefaults.standard.set(positions, forKey: playbackPositionsKey)
        lastSavedTime = currentTime
        print("💾 Saved playback position: \(AudioFormatters.formatDuration(currentTime)) for \(currentArticle?.title ?? "podcast")")
    }

    /// Load the saved playback position for a given audio URL
    func getSavedPlaybackPosition(for audioUrl: String) -> TimeInterval? {
        let positions = UserDefaults.standard.dictionary(forKey: playbackPositionsKey) as? [String: Double] ?? [:]
        return positions[audioUrl]
    }

    /// Check if an article has a saved playback position
    func hasSavedPosition(for article: Article) -> Bool {
        guard let audioUrl = article.audioUrl else { return false }
        return getSavedPlaybackPosition(for: audioUrl) != nil
    }

    /// Get formatted saved position for display (e.g., "Resume from 12:34")
    func getFormattedSavedPosition(for article: Article) -> String? {
        guard let audioUrl = article.audioUrl,
              let position = getSavedPlaybackPosition(for: audioUrl) else { return nil }
        return AudioFormatters.formatDuration(position)
    }

    /// Clear the saved playback position for a given audio URL
    private func clearPlaybackPosition(for audioUrl: String) {
        var positions = UserDefaults.standard.dictionary(forKey: playbackPositionsKey) as? [String: Double] ?? [:]
        positions.removeValue(forKey: audioUrl)
        UserDefaults.standard.set(positions, forKey: playbackPositionsKey)
        print("🗑️ Cleared playback position for \(audioUrl)")
    }

    /// Restore playback position if available
    private func restorePlaybackPosition() {
        guard let audioUrl = currentArticle?.audioUrl,
              let savedPosition = getSavedPlaybackPosition(for: audioUrl),
              savedPosition > 0 else { return }

        // Set flag to prevent saving during restoration
        isRestoringPosition = true
        print("⏮️ Will restore to position: \(AudioFormatters.formatDuration(savedPosition))")

        // Wait for duration to be available, then seek
        Task {
            // Wait for duration to become available (poll with retries)
            // Increased timeout to 10 seconds to handle slow networks and large files
            var attempts = 0
            let maxAttempts = 100 // 10 seconds max (100 × 0.1s)

            // Check both the cached duration and the player item directly
            while attempts < maxAttempts {
                // Check duration from player item directly
                if let playerDuration = player?.currentItem?.duration.seconds,
                   playerDuration.isFinite,
                   playerDuration > 0 {
                    // Update cached duration
                    await MainActor.run {
                        self.duration = playerDuration
                    }
                    break
                }

                // Also check our cached duration
                if duration > 0 {
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                attempts += 1
            }

            await MainActor.run {
                if duration > 0 && savedPosition < duration - 30 {
                    let progress = savedPosition / duration
                    seek(to: progress)
                    lastSavedTime = savedPosition // Update to prevent immediate re-save
                    print("⏮️ Restored playback position: \(AudioFormatters.formatDuration(savedPosition))")
                } else if duration <= 0 {
                    print("⚠️ Could not restore position: duration not loaded after \(attempts) attempts")
                }
                // Clear flag after restoration attempt
                isRestoringPosition = false
            }
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

    /// Extract chapters from the audio asset
    /// For MP3 files, tries ID3 extraction first (richer metadata with URLs)
    /// Falls back to AVFoundation for M4A/AAC or if ID3 fails
    private func extractChapters(from asset: AVAsset) async {
        // Check if this is an MP3 file - if so, try ID3 first for richer metadata (URLs, artwork)
        if let audioUrlString = currentArticle?.audioUrl,
           let audioUrl = URL(string: audioUrlString),
           audioUrl.pathExtension.lowercased() == "mp3" {
            print("📖 MP3 detected - trying ID3 extraction first for chapter URLs")
            let foundID3Chapters = await extractID3Chapters(from: asset)
            if foundID3Chapters {
                return // ID3 succeeded with chapters
            }
            print("📖 ID3 extraction returned no chapters, falling back to AVFoundation")
        }

        // Use AVFoundation for M4A/AAC or as fallback for MP3
        await extractAVFoundationChapters(from: asset)
    }

    /// Extract chapters using AVFoundation (works for M4A/AAC and some MP3s)
    private func extractAVFoundationChapters(from asset: AVAsset) async {
        do {
            // Try to load chapter metadata groups
            let languages = try await asset.load(.availableChapterLocales).map { $0.identifier }
            let preferredLanguages = languages.isEmpty ? [Locale.current.identifier] : languages

            let chapterGroups = try await asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: preferredLanguages
            )

            guard !chapterGroups.isEmpty else {
                print("📖 No chapters found via AVFoundation")
                return
            }

            var extractedChapters: [PodcastChapter] = []

            for (index, group) in chapterGroups.enumerated() {
                let startTime = group.timeRange.start.seconds
                let endTime = (group.timeRange.start + group.timeRange.duration).seconds

                // Extract chapter title
                var title = "Chapter \(index + 1)"
                let imageUrl: String? = nil

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
            print("📖 Failed to extract chapters via AVFoundation: \(error)")
        }
    }

    /// Extract chapters from ID3 metadata (MP3 files) using OutcastID3
    /// Returns true if chapters were found and set
    @discardableResult
    private func extractID3Chapters(from asset: AVAsset) async -> Bool {
        // Get the audio URL from the current article
        guard let audioUrlString = currentArticle?.audioUrl,
              let audioUrl = URL(string: audioUrlString) else {
            print("📖 No audio URL available for ID3 chapter extraction")
            return false
        }

        // Only process MP3 files for ID3 chapters
        let pathExtension = audioUrl.pathExtension.lowercased()
        guard pathExtension == "mp3" else {
            print("📖 Skipping ID3 extraction for non-MP3 file: \(pathExtension)")
            return false
        }

        print("📖 Extracting ID3 chapters from: \(audioUrl.lastPathComponent)")

        do {
            let id3Chapters = try await ID3ChapterService.shared.extractChapters(from: audioUrl)

            if !id3Chapters.isEmpty {
                await MainActor.run {
                    self.chapters = id3Chapters.map { chapter in
                        PodcastChapter(
                            title: chapter.title,
                            startTime: chapter.startTime,
                            endTime: chapter.endTime,
                            imageUrl: nil,
                            url: chapter.url,
                            image: chapter.image
                        )
                    }.sorted { $0.startTime < $1.startTime }

                    print("📖 Extracted \(self.chapters.count) chapters from ID3 tags")
                    for chapter in self.chapters {
                        let hasArt = chapter.image != nil ? "🖼️" : ""
                        let hasUrl = chapter.url != nil ? "🔗" : ""
                        print("   - \(chapter.formattedStartTime): \(chapter.title) \(hasArt)\(hasUrl)")
                    }
                }
                return true
            } else {
                print("📖 No ID3 chapters found in MP3 file")
                return false
            }
        } catch {
            print("📖 Failed to extract ID3 chapters: \(error)")
            return false
        }
    }

    // MARK: - Chapter Prefetching

    /// Prefetch chapters for an article (call from article detail view)
    /// This fetches ID3 chapter data in the background so it's ready when playback starts
    func prefetchChapters(for article: Article) {
        guard let audioUrlString = article.audioUrl,
              let audioUrl = URL(string: audioUrlString),
              audioUrl.pathExtension.lowercased() == "mp3" else {
            return // Only prefetch for MP3 files
        }

        // Don't prefetch if already cached or in progress
        // Use atomic check-and-set to prevent race conditions
        guard prefetchedChapters[audioUrlString] == nil else {
            return
        }
        
        // Atomically check and insert to prevent multiple concurrent prefetch tasks
        guard prefetchingURLs.insert(audioUrlString).inserted else {
            return // Already being prefetched
        }
        print("📖 Prefetching chapters for: \(audioUrl.lastPathComponent)")

        Task {
            do {
                let id3Chapters = try await ID3ChapterService.shared.extractChapters(from: audioUrl)

                if !id3Chapters.isEmpty {
                    let podcastChapters = id3Chapters.map { chapter in
                        PodcastChapter(
                            title: chapter.title,
                            startTime: chapter.startTime,
                            endTime: chapter.endTime,
                            imageUrl: nil,
                            url: chapter.url,
                            image: chapter.image
                        )
                    }.sorted { $0.startTime < $1.startTime }

                    await MainActor.run {
                        self.prefetchedChapters[audioUrlString] = podcastChapters
                        self.prefetchingURLs.remove(audioUrlString)
                        print("📖 Prefetched \(podcastChapters.count) chapters for \(audioUrl.lastPathComponent)")
                    }
                } else {
                    _ = await MainActor.run {
                        self.prefetchingURLs.remove(audioUrlString)
                    }
                }
            } catch {
                _ = await MainActor.run {
                    self.prefetchingURLs.remove(audioUrlString)
                }
                print("📖 Prefetch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Check if chapters have been prefetched for an article
    func hasPrefetchedChapters(for article: Article) -> Bool {
        guard let audioUrl = article.audioUrl else { return false }
        return prefetchedChapters[audioUrl] != nil
    }

    /// Use prefetched chapters if available, otherwise extract normally
    private func usePrefetchedOrExtractChapters(from asset: AVAsset) async {
        // Check for prefetched chapters first
        if let audioUrlString = currentArticle?.audioUrl,
           let cached = prefetchedChapters[audioUrlString] {
            print("📖 Using prefetched chapters (\(cached.count) chapters)")
            self.chapters = cached
            // Clear from cache after use to free memory
            prefetchedChapters.removeValue(forKey: audioUrlString)
            return
        }

        // Fall back to normal extraction
        await extractChapters(from: asset)
    }
}
