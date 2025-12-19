//
//  AIChapterListView.swift
//  Today
//
//  View for displaying and navigating AI-generated podcast chapters
//

import SwiftUI

struct AIChapterListView: View {
    let chapters: [AIChapterData]
    let currentTime: TimeInterval
    let onChapterTap: (AIChapterData) -> Void
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accentColor.color)
                Text("AI Chapters")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 4)

            ForEach(chapters) { chapter in
                ChapterRow(
                    chapter: chapter,
                    isActive: isChapterActive(chapter),
                    onTap: { onChapterTap(chapter) }
                )
            }
        }
    }

    private func isChapterActive(_ chapter: AIChapterData) -> Bool {
        let isAfterStart = currentTime >= chapter.startTime
        if let endTime = chapter.endTime {
            return isAfterStart && currentTime < endTime
        }
        // For the last chapter (no end time), check if we're past its start
        guard let lastChapter = chapters.last else { return false }
        return chapter.id == lastChapter.id && isAfterStart
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let chapter: AIChapterData
    let isActive: Bool
    let onTap: () -> Void
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp
                Text(formatTime(chapter.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isActive ? accentColor.color : .secondary)
                    .frame(width: 44, alignment: .leading)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .font(.subheadline.weight(isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? accentColor.color : .primary)
                        .lineLimit(2)

                    if !chapter.summary.isEmpty && chapter.summary != "Chapter segment" {
                        Text(chapter.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !chapter.keywords.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(chapter.keywords.prefix(3), id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accentColor.color.opacity(0.1))
                                    .foregroundStyle(accentColor.color)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                Spacer()

                // Play indicator
                if isActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor.color)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isActive ? accentColor.color.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Compact Chapter View (for Now Playing)

struct CompactChapterView: View {
    let chapter: AIChapterData
    let isActive: Bool
    let onTap: () -> Void
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(formatTime(chapter.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isActive ? accentColor.color : .secondary)

                Text(chapter.title)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? accentColor.color : .primary)
                    .lineLimit(1)

                Spacer()

                if isActive {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(accentColor.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? accentColor.color.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Full Chapter List View (NavigationDestination)

struct FullChapterListView: View {
    let download: PodcastDownload
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        List {
            if let chapters = download.aiChapters, !chapters.isEmpty {
                Section {
                    ForEach(chapters) { chapter in
                        ChapterDetailRow(
                            chapter: chapter,
                            isActive: isChapterActive(chapter),
                            onTap: {
                                podcastPlayer.seekToAIChapter(chapter)
                            }
                        )
                    }
                } footer: {
                    Text("Generated by Apple Intelligence from episode transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No Chapters",
                    systemImage: "sparkles",
                    description: Text("Generate AI chapters after transcribing the episode.")
                )
            }
        }
        .navigationTitle("AI Chapters")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isChapterActive(_ chapter: AIChapterData) -> Bool {
        let currentTime = podcastPlayer.currentTime
        let isAfterStart = currentTime >= chapter.startTime
        if let endTime = chapter.endTime {
            return isAfterStart && currentTime < endTime
        }
        guard let chapters = download.aiChapters, let lastChapter = chapters.last else { return false }
        return chapter.id == lastChapter.id && isAfterStart
    }
}

private struct ChapterDetailRow: View {
    let chapter: AIChapterData
    let isActive: Bool
    let onTap: () -> Void
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(formatTime(chapter.startTime))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(isActive ? accentColor.color : .secondary)

                    if let endTime = chapter.endTime {
                        Text("→")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTime(endTime))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isActive {
                        Label("Playing", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(accentColor.color)
                    }
                }

                Text(chapter.title)
                    .font(.headline)
                    .foregroundStyle(isActive ? accentColor.color : .primary)

                if !chapter.summary.isEmpty && chapter.summary != "Chapter segment" {
                    Text(chapter.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !chapter.keywords.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chapter.keywords, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(accentColor.color.opacity(0.1))
                                .foregroundStyle(accentColor.color)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? accentColor.color.opacity(0.05) : nil)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    let sampleChapters = [
        AIChapterData(
            title: "Introduction",
            summary: "Welcome to the show and overview of today's topics",
            startTime: 0,
            endTime: 180,
            keywords: ["intro", "welcome"]
        ),
        AIChapterData(
            title: "Main Discussion",
            summary: "Deep dive into the primary subject matter",
            startTime: 180,
            endTime: 900,
            keywords: ["discussion", "analysis", "deep-dive"]
        ),
        AIChapterData(
            title: "Wrap Up",
            summary: "Concluding thoughts and next steps",
            startTime: 900,
            endTime: 1200,
            keywords: ["conclusion"]
        )
    ]

    return NavigationStack {
        ScrollView {
            AIChapterListView(
                chapters: sampleChapters,
                currentTime: 200,
                onChapterTap: { chapter in
                    print("Tapped: \(chapter.title)")
                }
            )
            .padding()
        }
    }
}
