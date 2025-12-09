//
//  NotificationManager.swift
//  Today
//
//  Manages local notifications for new feed articles
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    
    // Notification content length limits
    private let maxSubtitleLength = 100
    private let maxSummaryLength = 97 // Leave room for "..."
    
    private init() {}
    
    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            print(granted ? "✅ Notification permission granted" : "⚠️ Notification permission denied")
            return granted
        } catch {
            print("❌ Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check current notification authorization status
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    /// Post notifications for new articles from a feed
    /// If multiple articles, generates an AI summary and posts a single grouped notification
    func postNotificationsForNewArticles(feed: Feed, newArticles: [Article]) async {
        guard !newArticles.isEmpty else { return }
        
        // Check if notifications are enabled for this feed
        guard feed.notificationsEnabled else {
            print("🔕 Notifications disabled for feed: \(feed.title)")
            return
        }
        
        // Check authorization
        let status = await getAuthorizationStatus()
        guard status == .authorized else {
            print("⚠️ Notifications not authorized (status: \(status.rawValue))")
            return
        }
        
        // If we have multiple articles, group them with an AI summary
        if newArticles.count > 1 {
            await postGroupedNotification(feed: feed, articles: newArticles)
        } else if let article = newArticles.first {
            await postSingleNotification(feed: feed, article: article)
        }
    }
    
    /// Post a single notification for one new article
    private func postSingleNotification(feed: Feed, article: Article) async {
        let content = UNMutableNotificationContent()
        content.title = feed.title
        content.body = article.title
        content.sound = .default
        
        // Add subtitle with article description if available
        if let description = article.articleDescription?.htmlToPlainText.prefix(maxSubtitleLength) {
            content.subtitle = String(description)
        }
        
        // Add user info for deep linking
        content.userInfo = [
            "feedID": feed.persistentModelID.uriRepresentation().absoluteString,
            "articleID": article.persistentModelID.uriRepresentation().absoluteString,
            "type": "single_article"
        ]
        
        // Thread identifier for grouping notifications by feed
        content.threadIdentifier = "feed-\(feed.persistentModelID.hashValue)"
        
        // Create request with unique identifier
        let identifier = "article-\(article.persistentModelID.hashValue)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📬 Posted notification for article: \(article.title)")
        } catch {
            print("❌ Failed to post notification: \(error.localizedDescription)")
        }
    }
    
    /// Post a grouped notification with AI summary for multiple articles
    private func postGroupedNotification(feed: Feed, articles: [Article]) async {
        let content = UNMutableNotificationContent()
        content.title = feed.title
        content.sound = .default
        
        // Generate AI summary of the articles
        let summary = await generateNotificationSummary(articles: articles)
        
        if let summary = summary {
            // Use AI-generated summary
            content.body = "📰 \(articles.count) new articles"
            content.subtitle = summary
        } else {
            // Fallback: List article titles
            content.body = "📰 \(articles.count) new articles"
            let titles = articles.prefix(3).map { $0.title }.joined(separator: " • ")
            content.subtitle = titles
            if articles.count > 3 {
                content.subtitle! += " and \(articles.count - 3) more..."
            }
        }
        
        // Add user info for deep linking to feed
        content.userInfo = [
            "feedID": feed.persistentModelID.uriRepresentation().absoluteString,
            "articleCount": articles.count,
            "type": "grouped_articles"
        ]
        
        // Thread identifier for grouping notifications by feed
        content.threadIdentifier = "feed-\(feed.persistentModelID.hashValue)"
        
        // Set summary argument for notification grouping
        content.summaryArgument = feed.title
        content.summaryArgumentCount = articles.count
        
        // Create request with unique identifier
        let identifier = "feed-\(feed.persistentModelID.hashValue)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📬 Posted grouped notification for \(articles.count) articles from: \(feed.title)")
        } catch {
            print("❌ Failed to post grouped notification: \(error.localizedDescription)")
        }
    }
    
    /// Generate an AI summary for notification content
    /// Returns a concise summary suitable for notification subtitle
    private func generateNotificationSummary(articles: [Article]) async -> String? {
        // Use AIService to generate a brief summary
        let summary = await AIService.shared.summarizeArticles(articles)
        
        // Extract first sentence or limit to 100 characters for notification
        let sentences = summary.components(separatedBy: ". ")
        if let firstSentence = sentences.first, !firstSentence.isEmpty {
            let cleaned = firstSentence
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Limit to reasonable notification length
            if cleaned.count <= maxSubtitleLength {
                return cleaned
            } else {
                return String(cleaned.prefix(maxSummaryLength)) + "..."
            }
        }
        
        return nil
    }
    
    /// Remove all pending and delivered notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        print("🗑️ Cleared all notifications")
    }
    
    /// Remove notifications for a specific feed
    func clearNotificationsForFeed(_ feed: Feed) async {
        let threadIdentifier = "feed-\(feed.persistentModelID.hashValue)"
        
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let identifiersToRemove = notifications
            .filter { $0.request.content.threadIdentifier == threadIdentifier }
            .map { $0.request.identifier }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
        print("🗑️ Cleared \(identifiersToRemove.count) notifications for feed: \(feed.title)")
    }
}
