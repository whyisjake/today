//
//  SettingsView.swift
//  Today
//
//  Settings view for app preferences
//

import SwiftUI
import SwiftData
import AVFoundation

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var localizedName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum FontOption: String, CaseIterable, Identifiable {
    case serif = "Serif"
    case sansSerif = "Sans Serif"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .serif: return String(localized: "Serif")
        case .sansSerif: return String(localized: "Sans Serif")
        }
    }

    var fontFamily: String {
        switch self {
        case .serif:
            return "-apple-system-ui-serif, ui-serif, 'New York', Georgia, 'Times New Roman', serif"
        case .sansSerif:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        }
    }
}

enum ShortArticleBehavior: String, CaseIterable, Identifiable {
    case openInBrowser = "Open in Browser"
    case openInAppBrowser = "Open in Today Browser"
    case openInArticleView = "Open in Article View"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .openInBrowser: return String(localized: "Open in Browser")
        case .openInAppBrowser: return String(localized: "Open in Today Browser")
        case .openInArticleView: return String(localized: "Open in Article View")
        }
    }

    var description: String {
        switch self {
        case .openInBrowser: return String(localized: "Opens short articles directly in your default browser")
        case .openInAppBrowser: return String(localized: "Opens short articles in Today's built-in browser")
        case .openInArticleView: return String(localized: "Shows short articles in the article detail view")
        }
    }
}

enum AccentColorOption: String, CaseIterable, Identifiable {
    case red = "Red"
    case orange = "International Orange"
    case green = "Green"
    case blue = "Blue"
    case pink = "Pink"
    case purple = "Purple"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:
            return Color(red: 1.0, green: 0.231, blue: 0.188)
        case .orange:
            return Color(red: 1.0, green: 0.31, blue: 0.0) // International Orange (Aerospace)
        case .green:
            return Color(red: 0.196, green: 0.843, blue: 0.294)
        case .blue:
            return Color(red: 0.0, green: 0.478, blue: 1.0)
        case .pink:
            return Color(red: 1.0, green: 0.176, blue: 0.333)
        case .purple:
            return Color(red: 0.686, green: 0.322, blue: 0.871)
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @AppStorage("fontOption") private var fontOption: FontOption = .serif
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @AppStorage("shortArticleBehavior") private var shortArticleBehavior: ShortArticleBehavior = .openInAppBrowser
    @Environment(\.openURL) private var openURL

    // Get app version dynamically
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }

    private var selectedVoiceName: String {
        if selectedVoiceIdentifier.isEmpty {
            return "Default"
        }
        if let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            return voice.name
        }
        return "Default"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Font", selection: $fontOption) {
                        ForEach(FontOption.allCases) { option in
                            Text(option.localizedName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent Color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            ForEach(AccentColorOption.allCases) { option in
                                Button {
                                    accentColor = option
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 44, height: 44)

                                        if accentColor == option {
                                            Image(systemName: "checkmark")
                                                .font(.body.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    NavigationLink {
                        ShortArticleBehaviorPickerView(selectedBehavior: $shortArticleBehavior)
                    } label: {
                        HStack {
                            Text("Short Article Behavior")
                            Spacer()
                            Text(shortArticleBehavior.localizedName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Short articles have minimal content (less than 300 characters) and are indicated by an external link icon.")
                        .font(.caption)
                }

                Section("Audio") {
                    NavigationLink {
                        VoicePickerView(selectedVoiceIdentifier: $selectedVoiceIdentifier)
                    } label: {
                        HStack {
                            Text("Text-to-Speech Voice")
                            Spacer()
                            Text(selectedVoiceName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        DownloadsSettingsView()
                    } label: {
                        HStack {
                            Text("Downloaded Episodes")
                            Spacer()
                            Text(PodcastDownloadManager.shared.formattedTotalSize())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("Manage downloaded podcast episodes and storage.")
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today \(appVersion)")
                            .font(.headline)
                        Text("A modern RSS reader for iOS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Developer") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jake Spurlock")
                            .font(.headline)
                        Text("Software Engineer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        if let url = URL(string: "https://jakespurlock.com") {
                            openURL(url)
                        }
                    } label: {
                        Label("Website", systemImage: "globe")
                    }

                    Button {
                        if let url = URL(string: "https://github.com/whyisjake") {
                            openURL(url)
                        }
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    Button {
                        if let url = URL(string: "https://twitter.com/whyisjake") {
                            openURL(url)
                        }
                    } label: {
                        Label("Twitter", systemImage: "at")
                    }

                    Button {
                        if let url = URL(string: "https://linkedin.com/in/jakespurlock") {
                            openURL(url)
                        }
                    } label: {
                        Label("LinkedIn", systemImage: "person.crop.circle")
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text("Made with ♥️ in California")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                #if DEBUG
                Section("🧪 Debug - Review Testing") {
                    Button("Force Review Prompt") {
                        Task { @MainActor in
                            ReviewRequestManager.shared.forceReviewRequest()
                        }
                    }

                    Button("Reset Review Data") {
                        Task { @MainActor in
                            ReviewRequestManager.shared.resetAllReviewData()
                        }
                    }

                    Button("Show Review Status") {
                        Task { @MainActor in
                            print(ReviewRequestManager.shared.getReviewStatus())
                        }
                    }
                }
                .foregroundStyle(accentColor.color)
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Voice Picker View

struct VoicePickerView: View {
    @Binding var selectedVoiceIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var synthesizer = AVSpeechSynthesizer()

    // Group voices by language (exclude novelty/low-quality voices)
    private var voicesByLanguage: [(language: String, voices: [AVSpeechSynthesisVoice])] {
        // Hardcoded list of novelty voices to filter out (as of iOS 18)
        //
        // NOTE: This list uses name-based filtering rather than quality-based filtering because:
        // 1. AVSpeechSynthesisVoice.Quality doesn't distinguish novelty voices from standard voices
        // 2. Apple's voice quality enum only provides .default, .enhanced, and .premium tiers
        // 3. Novelty voices (like Zarvox, Bells, etc.) are marked as .default quality alongside
        //    legitimate standard voices, making quality-based filtering impractical
        //
        // This list may need periodic updates as Apple adds or removes voices in future iOS versions.
        // The voices listed here are confirmed novelty/character voices that are inappropriate for
        // article reading as of iOS 18.
        let unwantedVoiceNames = [
            "Zarvox", "Organ", "Bells", "Bad News", "Bahh", "Boing",
            "Bubbles", "Cellos", "Good News", "Trinoids", "Whisper",
            "Albert", "Fred", "Hysterical", "Junior", "Ralph",
            "Wobble", "Superstar", "Jester", "Kathy"
        ]

        // Filter out unwanted voices, keep enhanced and premium
        let filteredVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            // Remove novelty voices by name
            let isUnwanted = unwantedVoiceNames.contains { voice.name.contains($0) }
            return !isUnwanted
        }
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        // Group voices by language code
        let grouped = Dictionary(grouping: filteredVoices) { voice in
            voice.language
        }

        // Filter to only show voices matching the device's current language
        let currentLanguageVoices = grouped.filter { languageCode, _ in
            languageCode.hasPrefix(currentLanguage)
        }

        // Sort by language variant (e.g., en-US, en-GB, en-AU)
        let sorted = currentLanguageVoices.sorted { $0.key < $1.key }

        return sorted.map { (language: $0.key, voices: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedVoiceIdentifier = ""
                } label: {
                    HStack {
                        Text(String(localized: "Default (System Voice)"))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedVoiceIdentifier.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            ForEach(voicesByLanguage, id: \.language) { group in
                Section(header: Text(languageDisplayName(for: group.language))) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        Button {
                            // Select the voice immediately (shows checkmark)
                            selectedVoiceIdentifier = voice.identifier

                            // Preview the voice with a sample phrase
                            previewVoice(voice)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.name)
                                        .foregroundStyle(.primary)
                                    if voice.quality != .default {
                                        Text(qualityDescription(for: voice))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedVoiceIdentifier == voice.identifier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Select Voice"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func languageDisplayName(for languageCode: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forIdentifier: languageCode) ?? languageCode
    }

    private func qualityDescription(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .default:
            return "Standard"
        case .enhanced:
            return "Enhanced"
        case .premium:
            return "Premium"
        @unknown default:
            return "Standard"
        }
    }

    private func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        // Stop any currently playing preview
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Create preview utterance with localized text
        let previewText = String(localized: "This is the voice of %@", comment: "Voice preview sample text")
        let formattedText = String(format: previewText, voice.name)
        let utterance = AVSpeechUtterance(string: formattedText)
        utterance.voice = voice
        utterance.rate = 0.5 // Normal speech rate (same as default for audio player)

        synthesizer.speak(utterance)
    }
}

// MARK: - Short Article Behavior Picker View

struct ShortArticleBehaviorPickerView: View {
    @Binding var selectedBehavior: ShortArticleBehavior
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        List {
            ForEach(ShortArticleBehavior.allCases) { behavior in
                Button {
                    selectedBehavior = behavior
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(behavior.localizedName)
                                .foregroundStyle(.primary)
                            Text(behavior.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedBehavior == behavior {
                            Image(systemName: "checkmark")
                                .foregroundStyle(accentColor.color)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "Short Article Behavior"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Downloads Settings View

struct DownloadsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PodcastDownload.downloadedAt, order: .reverse) private var downloads: [PodcastDownload]
    @AppStorage("autoDeleteDownloadsAfterDays") private var autoDeleteDays: Int = 30
    @AppStorage("defaultEpisodeLimit") private var defaultEpisodeLimit: Int = 5
    @State private var showingDeleteAlert = false

    private let deleteOptions = [7, 14, 30, 60, 90, 0] // 0 = never
    private let episodeLimitOptions = [1, 2, 3, 5, 10, 20, 0] // 0 = unlimited

    var body: some View {
        List {
            // Storage summary
            Section {
                HStack {
                    Text("Total Storage Used")
                    Spacer()
                    Text(PodcastDownloadManager.shared.formattedTotalSize())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Downloaded Episodes")
                    Spacer()
                    Text("\(downloads.filter { $0.downloadStatus == .completed }.count)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            }

            // Episode limit setting
            Section {
                Picker("Keep episodes per feed", selection: $defaultEpisodeLimit) {
                    ForEach(episodeLimitOptions, id: \.self) { limit in
                        if limit == 0 {
                            Text("Unlimited").tag(limit)
                        } else {
                            Text("\(limit) episodes").tag(limit)
                        }
                    }
                }
            } header: {
                Text("Episode Limits")
            } footer: {
                Text("When downloading new episodes, older downloads from the same feed will be removed to stay within this limit. Individual feeds can override this setting.")
            }

            // Auto-delete setting
            Section {
                Picker("Auto-delete after", selection: $autoDeleteDays) {
                    ForEach(deleteOptions, id: \.self) { days in
                        if days == 0 {
                            Text("Never").tag(days)
                        } else {
                            Text("\(days) days").tag(days)
                        }
                    }
                }
            } header: {
                Text("Automatic Cleanup")
            } footer: {
                Text("Downloaded episodes will be automatically deleted after this period to save storage.")
            }

            // Stuck transcriptions section
            let stuckTranscriptions = downloads.filter { $0.isTranscriptionStuck }
            if !stuckTranscriptions.isEmpty {
                Section {
                    ForEach(stuckTranscriptions) { download in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(download.article?.title ?? "Unknown Episode")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Transcription stuck at \(Int(download.transcriptionProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Reset") {
                                download.resetTranscription()
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    Text("Stuck Transcriptions")
                } footer: {
                    Text("These transcriptions were interrupted. Reset them to try again.")
                }
            }

            // Downloaded episodes list
            if !downloads.isEmpty {
                Section {
                    ForEach(downloads.filter { $0.downloadStatus == .completed }) { download in
                        DownloadRowView(download: download)
                    }
                    .onDelete(perform: deleteDownloads)
                } header: {
                    Text("Downloaded Episodes")
                }
            }

            // Delete all button
            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete All Downloads")
                        Spacer()
                    }
                }
                .disabled(downloads.isEmpty)
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete All Downloads?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllDownloads()
            }
        } message: {
            Text("This will delete all downloaded episodes and their transcriptions. This action cannot be undone.")
        }
    }

    private func deleteDownloads(at offsets: IndexSet) {
        let completedDownloads = downloads.filter { $0.downloadStatus == .completed }
        for index in offsets {
            let download = completedDownloads[index]
            PodcastDownloadManager.shared.deleteDownload(for: download)
        }
    }

    private func deleteAllDownloads() {
        for download in downloads {
            PodcastDownloadManager.shared.deleteDownload(for: download)
        }
    }
}

// MARK: - Download Row View

struct DownloadRowView: View {
    let download: PodcastDownload

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let article = download.article {
                Text(article.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let fileSize = download.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if download.transcriptionStatus == .completed {
                        Label("Transcribed", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if download.chapterGenerationStatus == .completed {
                        Label("Chapters", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
            } else {
                Text("Unknown Episode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
