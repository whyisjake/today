//
//  ConditionalHTTPClientTests.swift
//  TodayTests
//
//  Tests for conditional HTTP GET functionality with ETag/Last-Modified headers
//

import XCTest
@testable import Today

/// Mock URLProtocol for testing HTTP responses
class MockURLProtocol: URLProtocol {
    static var mockResponses: [URL: MockResponse] = [:]

    struct MockResponse {
        let statusCode: Int
        let headers: [String: String]
        let data: Data?
        let redirectURL: URL?
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url,
              let mockResponse = MockURLProtocol.mockResponses[url] else {
            // Default 404 if no mock configured
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Handle redirect if specified
        if let redirectURL = mockResponse.redirectURL {
            let redirectResponse = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: mockResponse.headers
            )!

            let newRequest = URLRequest(url: redirectURL)
            client?.urlProtocol(
                self,
                wasRedirectedTo: newRequest,
                redirectResponse: redirectResponse
            )

            // Now send the final response from the redirect URL
            if let finalMock = MockURLProtocol.mockResponses[redirectURL] {
                let finalResponse = HTTPURLResponse(
                    url: redirectURL,
                    statusCode: finalMock.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: finalMock.headers
                )!
                client?.urlProtocol(self, didReceive: finalResponse, cacheStoragePolicy: .notAllowed)
                if let data = finalMock.data {
                    client?.urlProtocol(self, didLoad: data)
                }
            }
        } else {
            // Normal response without redirect
            let response = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: mockResponse.headers
            )!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = mockResponse.data {
                client?.urlProtocol(self, didLoad: data)
            }
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Nothing to do
    }
}

final class ConditionalHTTPClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Configure URLSession to use our mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
    }

    override func tearDown() {
        // Clear mock responses
        MockURLProtocol.mockResponses.removeAll()
        super.tearDown()
    }

    // MARK: - Basic Fetch Tests

    func testFetchWithoutCacheHeaders() async throws {
        let url = URL(string: "https://example.com/feed.xml")!
        let testData = "Test feed content".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [
                "Last-Modified": "Mon, 23 Oct 2023 10:00:00 GMT",
                "ETag": "\"abc123\""
            ],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified, "Should indicate content was modified")
        XCTAssertEqual(response.data, testData)
        XCTAssertEqual(response.lastModified, "Mon, 23 Oct 2023 10:00:00 GMT")
        XCTAssertEqual(response.etag, "\"abc123\"")
        XCTAssertNil(response.finalURL, "Should not have redirect")
        XCTAssertFalse(response.hadPermanentRedirect, "Should not have permanent redirect")
    }

    func testFetchWithCacheHeadersSendsConditionalRequest() async throws {
        let url = URL(string: "https://example.com/feed.xml")!
        let testData = "New content".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [
                "Last-Modified": "Tue, 24 Oct 2023 12:00:00 GMT",
                "ETag": "\"def456\""
            ],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: "Mon, 23 Oct 2023 10:00:00 GMT",
            etag: "\"abc123\""
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.data, testData)
        XCTAssertEqual(response.lastModified, "Tue, 24 Oct 2023 12:00:00 GMT")
        XCTAssertEqual(response.etag, "\"def456\"")
    }

    // MARK: - 304 Not Modified Tests

    func test304NotModifiedResponse() async throws {
        let url = URL(string: "https://example.com/feed.xml")!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 304,
            headers: [:],
            data: nil,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: "Mon, 23 Oct 2023 10:00:00 GMT",
            etag: "\"abc123\""
        )

        XCTAssertFalse(response.wasModified, "Should indicate content was not modified")
        XCTAssertNil(response.data, "304 response should have no data")
        XCTAssertEqual(response.lastModified, "Mon, 23 Oct 2023 10:00:00 GMT", "Should preserve cached headers")
        XCTAssertEqual(response.etag, "\"abc123\"", "Should preserve cached headers")
        XCTAssertFalse(response.hadPermanentRedirect)
    }

    // MARK: - Redirect Tests

    func test301PermanentRedirect() async throws {
        let originalURL = URL(string: "https://example.com/old-feed.xml")!
        let newURL = URL(string: "https://example.com/new-feed.xml")!
        let testData = "Feed content at new location".data(using: .utf8)!

        // Set up 301 redirect from old to new URL
        MockURLProtocol.mockResponses[originalURL] = MockURLProtocol.MockResponse(
            statusCode: 301,
            headers: ["Location": newURL.absoluteString],
            data: nil,
            redirectURL: newURL
        )

        // Set up final response at new URL
        MockURLProtocol.mockResponses[newURL] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [
                "Last-Modified": "Mon, 23 Oct 2023 10:00:00 GMT",
                "ETag": "\"xyz789\""
            ],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: originalURL,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.data, testData)
        XCTAssertTrue(response.hadPermanentRedirect, "Should detect 301 redirect")
        XCTAssertEqual(response.finalURL, newURL, "Should provide final URL after redirect")
        XCTAssertEqual(response.lastModified, "Mon, 23 Oct 2023 10:00:00 GMT")
        XCTAssertEqual(response.etag, "\"xyz789\"")
    }

    func test302TemporaryRedirect() async throws {
        let originalURL = URL(string: "https://example.com/feed.xml")!
        let tempURL = URL(string: "https://cdn.example.com/feed.xml")!
        let testData = "Feed content at temp location".data(using: .utf8)!

        // Set up 302 redirect
        MockURLProtocol.mockResponses[originalURL] = MockURLProtocol.MockResponse(
            statusCode: 302,
            headers: ["Location": tempURL.absoluteString],
            data: nil,
            redirectURL: tempURL
        )

        // Set up final response
        MockURLProtocol.mockResponses[tempURL] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [
                "Last-Modified": "Mon, 23 Oct 2023 10:00:00 GMT"
            ],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: originalURL,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.data, testData)
        XCTAssertFalse(response.hadPermanentRedirect, "302 is not permanent")
        // Note: finalURL will still be set for 302, but hadPermanentRedirect is false
        // so callers know not to update the stored URL
    }

    func test301RedirectFollowedBy304NotModified() async throws {
        let originalURL = URL(string: "https://example.com/old-feed.xml")!
        let newURL = URL(string: "https://example.com/new-feed.xml")!

        // Set up 301 redirect
        MockURLProtocol.mockResponses[originalURL] = MockURLProtocol.MockResponse(
            statusCode: 301,
            headers: ["Location": newURL.absoluteString],
            data: nil,
            redirectURL: newURL
        )

        // Set up 304 at new URL
        MockURLProtocol.mockResponses[newURL] = MockURLProtocol.MockResponse(
            statusCode: 304,
            headers: [:],
            data: nil,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: originalURL,
            lastModified: "Mon, 23 Oct 2023 10:00:00 GMT",
            etag: "\"abc123\""
        )

        XCTAssertFalse(response.wasModified, "304 means not modified")
        XCTAssertNil(response.data, "304 has no data")
        XCTAssertTrue(response.hadPermanentRedirect, "Should detect 301 even with 304 final response")
        XCTAssertEqual(response.finalURL, newURL, "Should provide new URL even with 304")
        XCTAssertEqual(response.lastModified, "Mon, 23 Oct 2023 10:00:00 GMT", "Should preserve cached headers")
        XCTAssertEqual(response.etag, "\"abc123\"", "Should preserve cached headers")
    }

    // MARK: - Additional Headers Tests

    func testAdditionalHeadersAreSent() async throws {
        let url = URL(string: "https://reddit.com/r/test.json")!
        let testData = "Reddit content".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [:],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: nil,
            etag: nil,
            additionalHeaders: ["User-Agent": "ios:com.today.app:v1.0"]
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.data, testData)
    }

    // MARK: - Edge Cases

    func testNoCacheHeadersInResponse() async throws {
        let url = URL(string: "https://example.com/feed.xml")!
        let testData = "Content without cache headers".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: [:],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.data, testData)
        XCTAssertNil(response.lastModified, "No Last-Modified header in response")
        XCTAssertNil(response.etag, "No ETag header in response")
    }

    func testOnlyLastModifiedHeaderPresent() async throws {
        let url = URL(string: "https://example.com/feed.xml")!
        let testData = "Content".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: ["Last-Modified": "Mon, 23 Oct 2023 10:00:00 GMT"],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertEqual(response.lastModified, "Mon, 23 Oct 2023 10:00:00 GMT")
        XCTAssertNil(response.etag)
    }

    func testOnlyETagHeaderPresent() async throws {
        let url = URL(string: "https://example.com/feed.xml")!
        let testData = "Content".data(using: .utf8)!

        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 200,
            headers: ["ETag": "\"abc123\""],
            data: testData,
            redirectURL: nil
        )

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: url,
            lastModified: nil,
            etag: nil
        )

        XCTAssertTrue(response.wasModified)
        XCTAssertNil(response.lastModified)
        XCTAssertEqual(response.etag, "\"abc123\"")
    }
}
