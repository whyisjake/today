//
//  SettingsView.swift
//  Today
//
//  Settings view for app preferences
//

import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today v1.0")
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
                        if let url = URL(string: "https://github.com/jakespurlock") {
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
                        Label("Twitter/X", systemImage: "at")
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
                        Text("Made with ♥️ in San Francisco")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
