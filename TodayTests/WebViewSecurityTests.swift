//
//  WebViewSecurityTests.swift
//  TodayTests
//
//  Guards the WebView hardening from U1: untrusted feed / Reddit HTML must not be able to
//  execute JavaScript, the rendered document must carry a restrictive Content-Security-Policy,
//  and — critically — the app's own height measurement must keep working under both.
//

import XCTest
import SwiftUI
import WebKit
@testable import Today

@MainActor
final class WebViewSecurityTests: XCTestCase {

    // MARK: - Helpers

    /// A representative article body, in the same shape a feed would deliver it.
    private let sampleArticleHTML = """
    <p>First paragraph of the article body.</p>
    <p>\(String(repeating: "Filler sentence for measurable height. ", count: 120))</p>
    <img src="https://example.com/photo.jpg">
    """

    private func styledArticleHTML(_ html: String) -> String {
        createStyledHTML(from: html, colorScheme: .light, accentColor: .orange, fontOption: .serif)
    }

    private func makePostWebView(html: String) -> PostWebView {
        PostWebView(html: html, height: .constant(0), colorScheme: .light, accentColor: .orange, fontOption: .serif)
    }

    private func makeCommentWebView(html: String) -> CommentWebView {
        CommentWebView(html: html, height: .constant(0), colorScheme: .light, accentColor: .orange, fontOption: .serif)
    }

    /// Loads `html` into a WebView built from `configuration`, waits for `didFinish`, then
    /// evaluates `script` from the host side and returns the result.
    private func loadAndEvaluate(
        html: String,
        configuration: WKWebViewConfiguration,
        script: String
    ) async throws -> Any? {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate

        let finished = expectation(description: "WebView finished loading")
        delegate.onFinish = { finished.fulfill() }
        delegate.onFail = { _ in finished.fulfill() }

        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [finished], timeout: 20)

        XCTAssertNil(delegate.failure, "Representative document failed to load: \(String(describing: delegate.failure))")
        return try await webView.evaluateJavaScript(script)
    }

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        var onFail: ((Error) -> Void)?
        private(set) var failure: Error?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failure = error
            onFail?(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failure = error
            onFail?(error)
        }
    }

    // MARK: - Happy path: the template carries the CSP and still carries the content

    func testArticleTemplateContainsContentSecurityPolicyAndArticleContent() {
        let document = styledArticleHTML("<p>Hello from the feed.</p>")

        XCTAssertTrue(
            document.contains(WebViewSecurity.contentSecurityPolicyMeta),
            "createStyledHTML must emit the Content-Security-Policy meta tag"
        )
        XCTAssertTrue(document.contains("<p>Hello from the feed.</p>"), "Article content must survive the wrapper")
        XCTAssertTrue(document.contains("default-src 'none'"), "CSP must default-deny")
    }

    func testRedditTemplatesContainContentSecurityPolicy() {
        let post = makePostWebView(html: "<p>selftext</p>")
            .createStyledHTML(from: "<p>selftext</p>", colorScheme: .light, accentColor: .orange, fontOption: .serif)
        let comment = makeCommentWebView(html: "<p>body</p>")
            .createStyledHTML(from: "<p>body</p>", colorScheme: .light, accentColor: .orange, fontOption: .serif)

        for document in [post, comment] {
            XCTAssertTrue(document.contains(WebViewSecurity.contentSecurityPolicyMeta), "Reddit wrapper must emit the CSP meta")
            XCTAssertTrue(document.contains("default-src 'none'"))
        }
        XCTAssertTrue(post.contains("<p>selftext</p>"))
        XCTAssertTrue(comment.contains("<p>body</p>"))
    }

    /// The whole point of the policy: it names no `script-src`, so `default-src 'none'` denies
    /// every script source — external, inline, and inline event handlers alike.
    func testContentSecurityPoliciesGrantNoScriptSource() {
        for policy in [WebViewSecurity.contentSecurityPolicyMeta, WebViewSecurity.embeddedMediaSecurityPolicyMeta] {
            XCTAssertTrue(policy.contains("default-src 'none'"), "Policy must default-deny: \(policy)")
            XCTAssertFalse(policy.contains("script-src"), "Policy must not grant any script source: \(policy)")
            XCTAssertFalse(policy.contains("'unsafe-eval'"), "Policy must not allow eval: \(policy)")
        }
        // The embedded-media wrapper additionally frames third-party players.
        XCTAssertTrue(WebViewSecurity.embeddedMediaSecurityPolicyMeta.contains("frame-src https:"))
        XCTAssertFalse(WebViewSecurity.contentSecurityPolicyMeta.contains("frame-src"), "Article/Reddit text wrappers must not frame anything")
    }

    // MARK: - Edge case: every content configuration factory disables page JavaScript

    func testContentWebViewConfigurationsDisableContentJavaScript() {
        XCTAssertFalse(
            WebViewPool.shared.makeConfiguration().defaultWebpagePreferences.allowsContentJavaScript,
            "WebViewPool backs the article body WebViews — page JS must be off"
        )
        XCTAssertFalse(
            WebViewSecurity.makeContentConfiguration().defaultWebpagePreferences.allowsContentJavaScript,
            "Reddit post/comment WebViews build their configuration here — page JS must be off"
        )

        // And the helper is not a no-op on an already-permissive configuration.
        let permissive = WKWebViewConfiguration()
        permissive.defaultWebpagePreferences.allowsContentJavaScript = true
        WebViewSecurity.disableContentJavaScript(permissive)
        XCTAssertFalse(permissive.defaultWebpagePreferences.allowsContentJavaScript)
    }

    // MARK: - Critical regression guard: height measurement still works

    /// `WebViewWithHeight.Coordinator`, `PostWebView.Coordinator` and `CommentWebView.Coordinator`
    /// all size themselves in `didFinish` via `evaluateJavaScript`. Disabling *page* JavaScript
    /// and applying `default-src 'none'` must not break that host-initiated evaluation — if it
    /// did, every article body would render blank or clipped.
    func testHeightMeasurementStillReturnsUsableHeightUnderHardenedConfiguration() async throws {
        let result = try await loadAndEvaluate(
            html: styledArticleHTML(sampleArticleHTML),
            configuration: WebViewSecurity.makeContentConfiguration(),
            script: "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        )

        let height = try XCTUnwrap(result as? CGFloat, "Height evaluation must return a number, got \(String(describing: result))")
        XCTAssertGreaterThan(height, 100, "Representative article must measure a usable height, not zero")
    }

    /// Same guard, but through the exact configuration instance the article WebViews use.
    func testHeightMeasurementWorksThroughWebViewPoolConfiguration() async throws {
        let result = try await loadAndEvaluate(
            html: styledArticleHTML(sampleArticleHTML),
            configuration: WebViewPool.shared.makeConfiguration(),
            script: "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        )

        let height = try XCTUnwrap(result as? CGFloat)
        XCTAssertGreaterThan(height, 100)
    }

    // MARK: - Error path: injected script does not execute

    /// A hostile feed item carrying `<script>` and an `onerror` handler. Neither may run.
    /// The flags are read back with a *host-initiated* evaluation, which is unaffected by the
    /// page-content restrictions — that asymmetry is exactly what is being asserted.
    func testInjectedScriptDoesNotExecute() async throws {
        let hostile = """
        <p>Innocent looking article.</p>
        <script>window.__xss = 1;</script>
        <img src="nope://broken" onerror="window.__xssHandler = 1;">
        """

        let result = try await loadAndEvaluate(
            html: styledArticleHTML(hostile),
            configuration: WebViewSecurity.makeContentConfiguration(),
            script: "String(window.__xss) + '|' + String(window.__xssHandler)"
        )

        XCTAssertEqual(result as? String, "undefined|undefined", "Neither <script> nor onerror= may execute in feed content")
    }

    /// The document must still render its trusted content while the injected script is inert.
    func testHostileDocumentStillRendersItsTextContent() async throws {
        let hostile = """
        <p>Innocent looking article.</p>
        <script>window.__xss = 1;</script>
        """

        let result = try await loadAndEvaluate(
            html: styledArticleHTML(hostile),
            configuration: WebViewSecurity.makeContentConfiguration(),
            script: "document.body.innerText"
        )

        let text = try XCTUnwrap(result as? String)
        XCTAssertTrue(text.contains("Innocent looking article."), "Content must still render, got: \(text)")
        XCTAssertFalse(text.contains("window.__xss"), "Script source must not be rendered as text")
    }
}
