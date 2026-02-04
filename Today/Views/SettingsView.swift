//
//  SettingsView.swift
//  Today
//
//  Settings view for app preferences
//

import SwiftUI
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
        #if os(iOS)
        NavigationStack {
            iOSSettingsContent
                .navigationTitle("Settings")
        }
        #else
        macOSSettingsContent
        #endif
    }

    // MARK: - iOS Settings

    #if os(iOS)
    private var iOSSettingsContent: some View {
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
    }
    #endif

    // MARK: - macOS Settings

    #if os(macOS)
    private var macOSSettingsContent: some View {
        TabView {
            // General Tab
            macOSGeneralTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            // Reading Tab
            macOSReadingTab
                .tabItem {
                    Label("Reading", systemImage: "doc.text")
                }

            // Audio Tab
            macOSAudioTab
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }

            // About Tab
            macOSAboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 500, minHeight: 350)
        .padding()
    }

    private var macOSGeneralTab: some View {
        Form {
            // Appearance
            LabeledContent("Appearance:") {
                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Font
            LabeledContent("Article Font:") {
                Picker("", selection: $fontOption) {
                    ForEach(FontOption.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Accent Color
            LabeledContent("Accent Color:") {
                HStack(spacing: 10) {
                    ForEach(AccentColorOption.allCases) { option in
                        Button {
                            accentColor = option
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 28, height: 28)
                                if accentColor == option {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2)
                                        .frame(width: 28, height: 28)
                                    Circle()
                                        .strokeBorder(.primary.opacity(0.3), lineWidth: 1)
                                        .frame(width: 30, height: 30)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(option.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var macOSReadingTab: some View {
        Form {
            LabeledContent {
                Picker("", selection: $shortArticleBehavior) {
                    ForEach(ShortArticleBehavior.allCases) { behavior in
                        Text(behavior.localizedName).tag(behavior)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Short Articles")
                        .font(.headline)
                    Text("Articles with minimal content (less than 300 characters)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var macOSAudioTab: some View {
        Form {
            LabeledContent("Text-to-Speech Voice:") {
                Picker("", selection: $selectedVoiceIdentifier) {
                    Text("Default (System Voice)").tag("")
                    Divider()
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 250)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        let unwantedVoiceNames = [
            "Zarvox", "Organ", "Bells", "Bad News", "Bahh", "Boing",
            "Bubbles", "Cellos", "Good News", "Trinoids", "Whisper",
            "Albert", "Fred", "Hysterical", "Junior", "Ralph",
            "Wobble", "Superstar", "Jester", "Kathy"
        ]
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let isUnwanted = unwantedVoiceNames.contains { voice.name.contains($0) }
                return !isUnwanted && voice.language.hasPrefix(currentLanguage)
            }
            .sorted { $0.name < $1.name }
    }

    private var macOSAboutTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 20)
                
                // App Icon and Name
                VStack(spacing: 12) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(accentColor.color)

                    Text("Today")
                        .font(.title.bold())
                    Text(appVersion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("A modern RSS reader")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.horizontal, 60)

                HStack(spacing: 4) {
                    Text("Made with")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("in California by Jake Spurlock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    Link(destination: URL(string: "https://twitter.com/whyisjake")!) {
                        Image(systemName: "at")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/whyisjake")!) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Link(destination: URL(string: "https://www.linkedin.com/in/jakespurlock")!) {
                        Image(systemName: "person.crop.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Link(destination: URL(string: "https://jakespurlock.com")!) {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
    #endif
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #endif
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #endif
    }
}
