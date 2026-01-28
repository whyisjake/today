//
//  ArticleAudioPlayer.swift
//  Today
//
//  Text-to-speech audio player for reading articles aloud
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
class ArticleAudioPlayer: NSObject, ObservableObject {
    // Access selected voice from UserDefaults
    private var selectedVoiceIdentifier: String {
        UserDefaults.standard.string(forKey: "selectedVoiceIdentifier") ?? ""
    }
    static let shared = ArticleAudioPlayer()

    private let synthesizer = AVSpeechSynthesizer()
    
    // Playback rate limits
    private static let minPlaybackRate: Float = 0.3
    private static let maxPlaybackRate: Float = 2.0

    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentArticle: Article?
    @Published var progress: Double = 0.0 // 0.0 to 1.0
    @Published var playbackRate: Float = 0.5 // 0.5 actual rate = "1x" normal speed for display

    private var currentUtterance: AVSpeechUtterance?
    private var fullText: String = ""
    private var characterIndex: Int = 0
    private var isAdjustingPlayback = false // Flag to prevent delegate interference during speed/seek changes

    // Cache artwork to avoid reloading on every Now Playing update
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkArticleId: PersistentIdentifier?

    override private init() {
        super.init()
        synthesizer.delegate = self
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSessionForPlayback() {
        #if os(iOS)
        do {
            // Use .playback category for text-to-speech (allows background playback)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
        // macOS doesn't require explicit audio session configuration
    }

    private func restoreAmbientAudioSession() {
        #if os(iOS)
        do {
            // Restore .ambient category (for videos/GIFs that mix with other audio)
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to restore audio session: \(error)")
        }
        #endif
        // macOS doesn't require explicit audio session configuration
    }

    // MARK: - Helper Methods
    
    private func createUtterance(text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        
        if !selectedVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
        }
        
        utterance.rate = playbackRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        return utterance
    }

    // MARK: - Playback Control

    func play(article: Article) {
        // Configure audio session for playback
        configureAudioSessionForPlayback()

        // Set playing state immediately to keep mini player visible during transition
        let wasSwitchingArticles = isPlaying
        isPlaying = true
        isPaused = false

        // Set flag to prevent delegate from resetting state during article switch
        if wasSwitchingArticles {
            isAdjustingPlayback = true
            synthesizer.stopSpeaking(at: .immediate)
        }

        currentArticle = article
        fullText = article.cleanText
        characterIndex = 0
        progress = 0.0

        // Create utterance
        let utterance = createUtterance(text: fullText)
        currentUtterance = utterance

        // Update Now Playing info
        updateNowPlayingInfo()

        // Start speaking
        synthesizer.speak(utterance)

        // Clear flag after delegate has processed - delay to ensure async didCancel completes
        if wasSwitchingArticles {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                isAdjustingPlayback = false
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        updateNowPlayingInfo()
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        progress = 0.0
        characterIndex = 0
        currentArticle = nil
        currentUtterance = nil
        clearNowPlayingInfo()

        // Clear artwork cache
        cachedArtwork = nil
        cachedArtworkArticleId = nil

        // Restore ambient audio session for videos/GIFs
        restoreAmbientAudioSession()
    }

    func togglePlayPause() {
        if isPlaying && !isPaused {
            pause()
        } else if isPaused {
            resume()
        } else if let article = currentArticle {
            play(article: article)
        }
    }

    // MARK: - Seeking Control

    func seek(to newProgress: Double) {
        guard (isPlaying || isPaused), currentArticle != nil else { return }

        let wasPlaying = isPlaying && !isPaused

        // Set flag to prevent delegate from resetting state
        isAdjustingPlayback = true

        // Stop current playback
        synthesizer.stopSpeaking(at: .immediate)

        // Calculate character position to seek to
        let seekPosition = Int(newProgress * Double(fullText.count))
        progress = newProgress

        // Create new utterance from seek position
        let remainingText = String(fullText.suffix(fullText.count - seekPosition))
        let utterance = createUtterance(text: remainingText)
        currentUtterance = utterance
        characterIndex = seekPosition

        // Resume playback if it was playing
        if wasPlaying {
            synthesizer.speak(utterance)
            isPlaying = true
            isPaused = false
        } else {
            // Keep paused state
            isPaused = true
            isPlaying = false
        }

        updateNowPlayingInfo()

        // Clear flag after playback adjustment is complete
        isAdjustingPlayback = false
    }

    // MARK: - Duration Estimation
    
    var estimatedDuration: TimeInterval {
        // Rough estimate: average speaking rate is ~150 words per minute at 0.5x (normal "1x" speed)
        // Adjust for current playback rate
        guard let article = currentArticle else { return 0 }
        let wordCount = article.cleanText.split(separator: " ").count
        let baseMinutes = Double(wordCount) / 150.0
        return (baseMinutes * 60.0) / Double(playbackRate)
    }
    
    // MARK: - Playback Rate Control
    
    /// Formats playback rate for display
    /// - Parameter speed: The actual AVSpeech rate (0.5 = "1x" normal speed)
    /// - Returns: Formatted string like "1x" or "1.25x"
    static func formatSpeed(_ speed: Float) -> String {
        // Display speed is 2x the actual rate (0.5 actual = "1x" display)
        let displaySpeed = speed * 2
        if displaySpeed.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(displaySpeed))x"
        } else {
            return String(format: "%.2fx", displaySpeed)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(Self.minPlaybackRate, min(Self.maxPlaybackRate, rate))

        // If currently playing, restart with new rate while preserving position
        if isPlaying || isPaused, currentArticle != nil {
            let wasPlaying = isPlaying && !isPaused
            let currentProgress = progress

            // Set flag to prevent delegate from resetting state
            isAdjustingPlayback = true

            // Preserve state explicitly before stopping (prevents mini player from disappearing)
            if wasPlaying {
                isPlaying = true
                isPaused = false
            } else {
                isPlaying = false
                isPaused = true
            }

            // Stop current playback
            synthesizer.stopSpeaking(at: .immediate)

            // Calculate character position to resume from
            let resumePosition = Int(currentProgress * Double(fullText.count))

            // Create new utterance from current position
            let remainingText = String(fullText.suffix(fullText.count - resumePosition))
            let utterance = createUtterance(text: remainingText)
            currentUtterance = utterance
            characterIndex = resumePosition

            // Resume playback if it was playing
            if wasPlaying {
                synthesizer.speak(utterance)
            }

            updateNowPlayingInfo()

            // Clear flag after playback adjustment is complete
            isAdjustingPlayback = false
        }
    }

    // MARK: - Now Playing Info (Lock Screen)

    private func updateNowPlayingInfo() {
        guard let article = currentArticle else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: article.title,
            MPMediaItemPropertyArtist: article.feed?.title ?? "Today RSS Reader",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress * estimatedDuration,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
            MPMediaItemPropertyPlaybackDuration: estimatedDuration
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
                        if let image = PlatformImage(data: data) {
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
    private func createFallbackArtwork() -> PlatformImage {
        let size = CGSize(width: 300, height: 300)

        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Background
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Speaker icon for TTS
            let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .medium)
            if let symbol = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: config) {
                let symbolSize = symbol.size
                let x = (size.width - symbolSize.width) / 2
                let y = (size.height - symbolSize.height) / 2
                symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(at: CGPoint(x: x, y: y))
            }
        }
        #elseif os(macOS)
        let image = NSImage(size: size)
        image.lockFocus()

        // Background
        NSColor.orange.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Speaker icon for TTS
        if let symbol = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil) {
            let symbolSize = CGSize(width: 100, height: 100)
            let x = (size.width - symbolSize.width) / 2
            let y = (size.height - symbolSize.height) / 2
            let tinted = symbol.copy() as! NSImage
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height))
        }

        image.unlockFocus()
        return image
        #endif
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
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ArticleAudioPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Speech started
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Update progress based on character position
            characterIndex = characterRange.location
            if !fullText.isEmpty {
                progress = Double(characterIndex) / Double(fullText.count)
            }
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            // Don't reset state if we're switching articles or if this isn't the current utterance
            let isCurrentUtterance = currentUtterance.map { ObjectIdentifier($0) == utteranceID } ?? false
            if !isAdjustingPlayback && isCurrentUtterance {
                isPlaying = false
                isPaused = false
                progress = 1.0
                updateNowPlayingInfo()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Don't reset state if we're in the middle of adjusting playback (speed/seek)
            if !isAdjustingPlayback {
                isPlaying = false
                isPaused = false
            }
        }
    }
}

// MARK: - Article Extension for Clean Text

extension Article {
    /// Returns cleaned article text suitable for text-to-speech
    var cleanText: String {
        // Start with title
        var text = title + ". "

        // Prioritize full content over description (same order as ArticleDetailSimple view)
        if let contentEncoded = contentEncoded, !contentEncoded.isEmpty {
            text += stripHTML(contentEncoded)
        } else if let content = content, !content.isEmpty {
            text += stripHTML(content)
        } else if let description = articleDescription, !description.isEmpty {
            text += stripHTML(description)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip HTML tags and decode entities for clean text
    private func stripHTML(_ html: String) -> String {
        // Remove HTML tags
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&lsquo;", with: "'")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&ldquo;", with: "\"")

        return decoded
    }
}
