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

@MainActor
class ArticleAudioPlayer: NSObject, ObservableObject {
    // Access selected voice from UserDefaults
    private var selectedVoiceIdentifier: String {
        UserDefaults.standard.string(forKey: "selectedVoiceIdentifier") ?? ""
    }
    static let shared = ArticleAudioPlayer()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentArticle: Article?
    @Published var progress: Double = 0.0 // 0.0 to 1.0
    @Published var playbackRate: Float = 0.5 // Default speaking rate

    private var currentUtterance: AVSpeechUtterance?
    private var fullText: String = ""
    private var characterIndex: Int = 0

    override private init() {
        super.init()
        synthesizer.delegate = self
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSessionForPlayback() {
        do {
            // Use .playback category for text-to-speech (allows background playback)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            print("🎙️ Configured audio session for speech playback")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func restoreAmbientAudioSession() {
        do {
            // Restore .ambient category (for videos/GIFs that mix with other audio)
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("🎙️ Restored ambient audio session")
        } catch {
            print("Failed to restore audio session: \(error)")
        }
    }

    // MARK: - Playback Control

    func play(article: Article) {
        // Configure audio session for playback
        configureAudioSessionForPlayback()
        // Stop current playback if any
        if isPlaying {
            stop()
        }

        currentArticle = article
        fullText = article.cleanText
        characterIndex = 0
        progress = 0.0

        // Create utterance
        let utterance = AVSpeechUtterance(string: fullText)

        // Use selected voice if available, otherwise use default voice for current language
        if !selectedVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
        }

        utterance.rate = playbackRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        currentUtterance = utterance

        // Update Now Playing info
        updateNowPlayingInfo()

        // Start speaking
        synthesizer.speak(utterance)
        isPlaying = true
        isPaused = false
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

    // MARK: - Playback Rate Control

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.3, min(2.0, rate)) // Clamp between 0.3x and 2.0x

        // If currently playing, restart with new rate
        if isPlaying, let article = currentArticle {
            let wasPlaying = !isPaused
            stop()
            play(article: article)
            if !wasPlaying {
                pause()
            }
        }
    }

    // MARK: - Now Playing Info (Lock Screen)

    private func updateNowPlayingInfo() {
        guard let article = currentArticle else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: article.title,
            MPMediaItemPropertyArtist: article.feed?.title ?? "Today RSS Reader",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress * Double(fullText.count),
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
            MPMediaItemPropertyPlaybackDuration: Double(fullText.count) / Double(playbackRate * 150) // Rough estimate
        ]

        // Add artwork if available (app icon as fallback)
        if let image = UIImage(named: "AppIcon") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
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
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ArticleAudioPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("🎙️ Started speaking article")
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
        Task { @MainActor in
            print("🎙️ Finished speaking article")
            isPlaying = false
            isPaused = false
            progress = 1.0
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("🎙️ Paused speaking")
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("🎙️ Resumed speaking")
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("🎙️ Cancelled speaking")
            isPlaying = false
            isPaused = false
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
