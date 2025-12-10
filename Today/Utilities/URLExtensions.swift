//
//  URLExtensions.swift
//  Today
//
//  Extension for URL to add UTM tracking parameters
//

import Foundation

extension URL {
    /// Adds UTM parameters to the URL for tracking shared links from the app
    /// - Parameters:
    ///   - source: The referrer (e.g., "today_app")
    ///   - medium: The marketing medium (e.g., "ios_share")
    ///   - campaign: The campaign name (optional)
    /// - Returns: A new URL with UTM parameters appended, or the original URL if parameters cannot be added
    func addingUTMParameters(source: String = "today_app", medium: String = "ios_share", campaign: String? = nil) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }
        
        // Initialize query items array if it doesn't exist
        var queryItems = components.queryItems ?? []
        
        // Add UTM parameters
        queryItems.append(URLQueryItem(name: "utm_source", value: source))
        queryItems.append(URLQueryItem(name: "utm_medium", value: medium))
        
        if let campaign = campaign {
            queryItems.append(URLQueryItem(name: "utm_campaign", value: campaign))
        }
        
        components.queryItems = queryItems
        
        // Return the modified URL, or the original if construction fails
        return components.url ?? self
    }
}
