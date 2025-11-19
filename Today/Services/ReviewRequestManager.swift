//
//  ReviewRequestManager.swift
//  Today
//
//  Manages App Store review requests with respectful timing
//

import Foundation
import StoreKit
import SwiftUI

@MainActor
class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    private init() {}

    // UserDefaults keys
    private let articlesReadCountKey = "articlesReadCount"
    private let lastReviewRequestVersionKey = "lastReviewRequestVersion"
    private let firstLaunchDateKey = "firstLaunchDate"

    // Thresholds for requesting reviews
    private let minimumArticlesBeforeReview = 20
    private let minimumDaysBeforeReview = 3

    /// Increment the article read count
    func incrementArticleReadCount() {
        let currentCount = UserDefaults.standard.integer(forKey: articlesReadCountKey)
        UserDefaults.standard.set(currentCount + 1, forKey: articlesReadCountKey)
    }

    /// Check if we should request a review and do so if conditions are met
    func requestReviewIfAppropriate() {
        // Don't spam users - only request once per version
        let currentVersion = getCurrentAppVersion()
        let lastRequestedVersion = UserDefaults.standard.string(forKey: lastReviewRequestVersionKey)

        if lastRequestedVersion == currentVersion {
            return
        }

        // Check if app has been used enough
        guard hasMetUsageRequirements() else {
            return
        }

        // Check if enough time has passed since first launch
        guard hasMetTimeRequirement() else {
            return
        }

        // Request review (iOS handles rate limiting automatically)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)

            // Mark that we requested a review for this version
            UserDefaults.standard.set(currentVersion, forKey: lastReviewRequestVersionKey)
        }
    }

    /// Check if user has used the app enough to warrant a review request
    private func hasMetUsageRequirements() -> Bool {
        let articlesRead = UserDefaults.standard.integer(forKey: articlesReadCountKey)
        return articlesRead >= minimumArticlesBeforeReview
    }

    /// Check if enough time has passed since first launch
    private func hasMetTimeRequirement() -> Bool {
        // Record first launch date if not set
        if UserDefaults.standard.object(forKey: firstLaunchDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchDateKey)
            return false
        }

        guard let firstLaunchDate = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date else {
            return false
        }

        let daysSinceFirstLaunch = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        return daysSinceFirstLaunch >= minimumDaysBeforeReview
    }

    /// Get current app version
    private func getCurrentAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version).\(build)"
    }

    /// Reset article count (useful for testing or if user resets data)
    func resetArticleCount() {
        UserDefaults.standard.set(0, forKey: articlesReadCountKey)
    }

    // MARK: - Testing & Debug Methods

    #if DEBUG
    /// Force a review request for testing (bypasses all requirements)
    func forceReviewRequest() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            print("🧪 DEBUG: Force requested app review")
        }
    }

    /// Reset all review tracking data (for testing fresh state)
    func resetAllReviewData() {
        UserDefaults.standard.removeObject(forKey: articlesReadCountKey)
        UserDefaults.standard.removeObject(forKey: lastReviewRequestVersionKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchDateKey)
        print("🧪 DEBUG: Reset all review tracking data")
    }

    /// Get current review status for debugging
    func getReviewStatus() -> String {
        let articlesRead = UserDefaults.standard.integer(forKey: articlesReadCountKey)
        let lastRequestedVersion = UserDefaults.standard.string(forKey: lastReviewRequestVersionKey) ?? "Never"
        let firstLaunchDate = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date
        let daysSinceLaunch = firstLaunchDate.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 } ?? 0

        return """
        📊 Review Status:
        - Articles Read: \(articlesRead)/\(minimumArticlesBeforeReview)
        - Days Since First Launch: \(daysSinceLaunch)/\(minimumDaysBeforeReview)
        - Last Requested Version: \(lastRequestedVersion)
        - Current Version: \(getCurrentAppVersion())
        - Will Show: \(hasMetUsageRequirements() && hasMetTimeRequirement())
        """
    }
    #endif
}
