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

/// Delegate to track HTTP redirects
private final class RedirectTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var finalURL: URL?
    var wasRedirected: Bool = false
    var hadPermanentRedirect: Bool = false

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        wasRedirected = true
        finalURL = request.url

        // Track 301 permanent redirects so we can update the stored URL
        if response.statusCode == 301 {
            hadPermanentRedirect = true
        }

        return request // Follow the redirect
    }
}

/// Helper for making conditional HTTP requests
enum ConditionalHTTPClient {

    /// Perform a conditional GET request with redirect tracking
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

        // Create a custom session with redirect tracking delegate
        let redirectTracker = RedirectTracker()
        let session = URLSession(
            configuration: .default,
            delegate: redirectTracker,
            delegateQueue: nil
        )

        defer {
            session.finishTasksAndInvalidate()
        }

        let (data, response) = try await session.data(for: request)

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

        // Check for 304 Not Modified
        if httpResponse.statusCode == 304 {
            return ConditionalHTTPResponse(
                data: nil,
                wasModified: false,
                lastModified: lastModified, // Keep existing values
                etag: etag,
                finalURL: redirectTracker.finalURL,
                hadPermanentRedirect: redirectTracker.hadPermanentRedirect
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
            finalURL: redirectTracker.finalURL,
            hadPermanentRedirect: redirectTracker.hadPermanentRedirect
        )
    }
}
