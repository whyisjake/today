//
//  ConditionalHTTPClient.swift
//  Today
//
//  Helper for making conditional HTTP requests with If-Modified-Since and If-None-Match headers
//

import Foundation

/// Response from a conditional HTTP fetch
struct ConditionalHTTPResponse: Sendable {
    let data: Data?
    let wasModified: Bool
    let lastModified: String?
    let etag: String?
    let finalURL: URL?
    let hadPermanentRedirect: Bool
}

/// Helper for making conditional HTTP requests
/// Uses URLSession.shared to avoid creating ephemeral sessions/delegates
enum ConditionalHTTPClient {

    /// Perform a conditional GET request
    /// - Parameters:
    ///   - url: The URL to fetch
    ///   - lastModified: Previous Last-Modified header value (optional)
    ///   - etag: Previous ETag header value (optional)
    ///   - additionalHeaders: Extra headers to include (e.g., User-Agent for Reddit)
    /// - Returns: ConditionalHTTPResponse with data (nil if 304), modification status, cache headers, and final URL
    static func conditionalFetch(
        url: URL,
        lastModified: String?,
        etag: String?,
        additionalHeaders: [String: String] = [:]
    ) async throws -> ConditionalHTTPResponse {
        var request = URLRequest(url: url)

        // Add conditional headers if we have cached values
        if let lastModified = lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        // Add any additional headers (e.g., User-Agent for Reddit)
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Use shared session - avoids creating ephemeral sessions/delegates that can cause crashes
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            // Non-HTTP response, treat as modified with no cache headers
            return ConditionalHTTPResponse(
                data: data,
                wasModified: true,
                lastModified: nil,
                etag: nil,
                finalURL: nil,
                hadPermanentRedirect: false
            )
        }

        // Check if URL changed (indicates redirect occurred)
        // URLSession.shared follows redirects automatically; response.url is the final URL
        let responseURL = httpResponse.url
        let wasRedirected = responseURL != nil && responseURL != url
        // Treat any redirect as potentially permanent (we can't distinguish 301 vs 302 with shared session)
        // This is conservative - we update the URL if it changed
        let finalURL = wasRedirected ? responseURL : nil

        // Check for 304 Not Modified
        if httpResponse.statusCode == 304 {
            return ConditionalHTTPResponse(
                data: nil,
                wasModified: false,
                lastModified: lastModified, // Keep existing values
                etag: etag,
                finalURL: finalURL,
                hadPermanentRedirect: wasRedirected
            )
        }

        // Extract new cache headers from response
        let newLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")

        return ConditionalHTTPResponse(
            data: data,
            wasModified: true,
            lastModified: newLastModified,
            etag: newEtag,
            finalURL: finalURL,
            hadPermanentRedirect: wasRedirected
        )
    }
}
