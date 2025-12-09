//
//  NotificationSettingsView.swift
//  Today
//
//  Settings view for managing notification preferences
//

import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingSystemSettings = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Status")
                            .font(.headline)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if notificationStatus == .denied {
                        Button("Settings") {
                            openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Permission")
            } footer: {
                Text("Enable notifications to receive updates when new articles are available from your feeds.")
            }
            
            if notificationStatus == .authorized {
                Section {
                    ForEach(feeds) { feed in
                        Toggle(isOn: Binding(
                            get: { feed.notificationsEnabled },
                            set: { newValue in
                                feed.notificationsEnabled = newValue
                                try? modelContext.save()
                                print(newValue ? "🔔 Enabled notifications for: \(feed.title)" : "🔕 Disabled notifications for: \(feed.title)")
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title)
                                    .font(.body)
                                Text(feed.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("Feed Notifications")
                } footer: {
                    Text("Enable notifications for individual feeds. When multiple articles arrive, they'll be grouped into a single notification with an AI summary.")
                }
                
                Section {
                    Button(role: .destructive) {
                        clearAllNotifications()
                    } label: {
                        Label("Clear All Notifications", systemImage: "bell.slash")
                    }
                } footer: {
                    Text("Remove all delivered notifications from the notification center.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkNotificationStatus()
        }
        .refreshable {
            await checkNotificationStatus()
        }
    }
    
    private var statusIcon: String {
        switch notificationStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .provisional:
            return "clock.circle.fill"
        case .ephemeral:
            return "clock.circle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch notificationStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .provisional:
            return .blue
        case .ephemeral:
            return .blue
        @unknown default:
            return .gray
        }
    }
    
    private var statusText: String {
        switch notificationStatus {
        case .authorized:
            return "Notifications are enabled"
        case .denied:
            return "Notifications are disabled. Tap Settings to enable."
        case .notDetermined:
            return "Notification permission not requested"
        case .provisional:
            return "Provisional authorization granted"
        case .ephemeral:
            return "Ephemeral authorization granted"
        @unknown default:
            return "Unknown status"
        }
    }
    
    private func checkNotificationStatus() async {
        notificationStatus = await NotificationManager.shared.getAuthorizationStatus()
    }
    
    private func openSystemSettings() {
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
    }
    
    private func clearAllNotifications() {
        NotificationManager.shared.clearAllNotifications()
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .modelContainer(for: [Feed.self, Article.self], inMemory: true)
}
