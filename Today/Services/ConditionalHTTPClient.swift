//
//  ConditionalHTTPClient.swift
//  Today
//
//  Helper for making conditional HTTP requests with If-Modified-Since and If-None-Match headers
//

import Foundation
import os

/// Response from a conditional HTTP fetch
struct ConditionalHTTPResponse: Sendable {
    let data: Data?
    let wasModified: Bool
    let lastModified: String?
    let etag: String?
    let finalURL: URL?
    let hadPermanentRedirect: Bool
}

/// Observes redirects for a single request so permanent ones can be told apart from
/// temporary ones.
///
/// `URLSession` follows redirects automatically but does not report what kind they were —
/// only that the final URL differs from the requested one. Distinguishing 301/308 from
/// 302/303/307 matters because callers rewrite the stored feed URL on a permanent redirect;
/// doing that for a temporary redirect would corrupt the subscription.
///
/// Attached per task rather than to the session, so nothing long-lived is retained by the
/// session — session-wide delegates were the source of an earlier crash.
private final class RedirectObserver: NSObject, URLSessionTaskDelegate {
    // OSAllocatedUnfairLock rather than NSLock: the delegate callback is async, and
    // NSLock's lock()/unlock() are unavailable from async contexts.
    private let permanent = OSAllocatedUnfairLock(initialState: false)

    var sawPermanentRedirect: Bool {
        permanent.withLock { $0 }
    }

    // Completion-handler variant rather than the `async` one on purpose: the async
    // overload makes the compiler emit an ObjC async thunk for this method, which
    // crashes SILGen (swift-frontend assertion in emitNativeToForeignThunk). This
    // variant is equivalent and compiles.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 301 Moved Permanently and 308 Permanent Redirect are the only permanent ones.
        // 302/303/307 are explicitly temporary and must not rewrite a stored URL.
        if response.statusCode == 301 || response.statusCode == 308 {
            permanent.withLock { $0 = true }
        }
        completionHandler(request) // keep following the redirect
    }
}

/// A response that carried a status the caller must not treat as feed content.
enum HTTPError: LocalizedError {
    case unexpectedStatus(code: Int, url: URL)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let code, let url):
            let reason: String
            switch code {
            case 401, 403:
                // The case that prompted this: Reddit blocks unauthenticated `.json`.
                reason = "access denied (\(code)) — this endpoint may require authentication"
            case 404, 410:
                reason = "not found (\(code)) — the feed may have moved or been removed"
            case 429:
                reason = "rate limited (429) — too many requests to this host"
            case 500...599:
                reason = "server error (\(code))"
            default:
                reason = "unexpected HTTP status \(code)"
            }
            return "\(url.host ?? url.absoluteString): \(reason)"
        }
    }
}

/// Helper for making conditional HTTP requests
enum ConditionalHTTPClient {

    /// How long a single feed request may take before it is abandoned.
    ///
    /// `URLSession.shared` cannot carry a custom configuration, so it was stuck with the
    /// 60s default — long enough for one unresponsive feed to dominate a whole sync.
    static let requestTimeout: TimeInterval = 15

    /// Ceiling for the whole transfer, including redirects and a slow trickle of bytes.
    static let resourceTimeout: TimeInterval = 30

    /// Session used for feed fetches.
    ///
    /// Deliberately *not* `URLSession.shared`: we need a configuration to set the timeouts
    /// above. The session itself still has no delegate — an earlier crash was traced to
    /// sessions with delegates — redirect observation is attached per task instead, so
    /// nothing outlives the request. A configurable session is also what makes
    /// `URLProtocol`-based tests possible; with `URLSession.shared` a registered mock
    /// protocol is silently ignored.
    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: config)
    }()

    /// Perform a conditional GET request
    /// - Parameters:
    ///   - url: The URL to fetch
    ///   - lastModified: Previous Last-Modified header value (optional)
    ///   - etag: Previous ETag header value (optional)
    ///   - additionalHeaders: Extra headers to include (e.g., User-Agent for Reddit)
    ///   - session: Session to fetch with. Defaults to the timeout-configured shared instance;
    ///     tests inject a session backed by a mock `URLProtocol`.
    /// - Returns: ConditionalHTTPResponse with data (nil if 304), modification status, cache headers, and final URL
    static func conditionalFetch(
        url: URL,
        lastModified: String?,
        etag: String?,
        additionalHeaders: [String: String] = [:],
        session: URLSession = defaultSession
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

        let redirectObserver = RedirectObserver()
        let (data, response) = try await session.data(for: request, delegate: redirectObserver)

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

        // Check if URL changed (indicates a redirect occurred). The session follows
        // redirects automatically; response.url is the final URL.
        let responseURL = httpResponse.url
        let wasRedirected = responseURL != nil && responseURL != url
        let finalURL = wasRedirected ? responseURL : nil

        // Only a 301/308 justifies rewriting a stored feed URL. The observer saw the
        // actual redirect status codes, so temporary redirects no longer masquerade as
        // permanent ones the way they did when this was inferred from the URL alone.
        let hadPermanentRedirect = wasRedirected && redirectObserver.sawPermanentRedirect

        // Check for 304 Not Modified
        if httpResponse.statusCode == 304 {
            return ConditionalHTTPResponse(
                data: nil,
                wasModified: false,
                lastModified: lastModified, // Keep existing values
                etag: etag,
                finalURL: finalURL,
                hadPermanentRedirect: hadPermanentRedirect
            )
        }

        // Anything that is not a success is not feed data.
        //
        // Only 304 used to be special-cased, so every other status fell through and the body was
        // handed to the parser as though it were a feed. When Reddit began answering `.json`
        // with a 403 and a 190 KB HTML block page, that surfaced to the user as
        // "JSON text did not start with array or object" — or as nothing at all — instead of
        // "this feed returned 403". Fail loudly here so the per-feed health record
        // (`lastSyncError`) names the real reason.
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.unexpectedStatus(
                code: httpResponse.statusCode,
                url: httpResponse.url ?? url
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
            hadPermanentRedirect: hadPermanentRedirect
        )
    }
}
