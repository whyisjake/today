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
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Voice Picker View

struct VoicePickerView: View {
    @Binding var selectedVoiceIdentifier: String
    @Environment(\.dismiss) private var dismiss

    // Group voices by language
    private var voicesByLanguage: [(language: String, voices: [AVSpeechSynthesisVoice])] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        // Group voices by language code
        let grouped = Dictionary(grouping: allVoices) { voice in
            voice.language
        }

        // Sort: current language first, then alphabetically
        let sorted = grouped.sorted { first, second in
            if first.key.hasPrefix(currentLanguage) && !second.key.hasPrefix(currentLanguage) {
                return true
            }
            if !first.key.hasPrefix(currentLanguage) && second.key.hasPrefix(currentLanguage) {
                return false
            }
            return first.key < second.key
        }

        return sorted.map { (language: $0.key, voices: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedVoiceIdentifier = ""
                    dismiss()
                } label: {
                    HStack {
                        Text("Default (System Voice)")
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
                            selectedVoiceIdentifier = voice.identifier
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.name)
                                        .foregroundStyle(.primary)
                                    Text(qualityDescription(for: voice))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
        .navigationTitle("Select Voice")
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
}
