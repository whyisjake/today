//
//  WebViewNavigationPolicyTests.swift
//  TodayTests
//
//  Guards U2: the navigation delegates deny by default.
//
//  Before U2 every `decidePolicyFor` handler in the app opened with
//  `if navigationType == .other { allow }`. JavaScript-initiated navigations, `<meta refresh>`,
//  iframe loads and auto-submitted forms are *all* classified `.other`, so a feed item that got
//  any script or markup past the other mitigations could navigate the WebView to
//  `file:///etc/passwd` and read the app container.
//
//  The decision now lives in one pure function, `WebViewSecurity.policy(for:url:isContentView:)`,
//  which is what most of this suite exercises — `WKNavigationAction` cannot be constructed from
//  test code, so testing through the delegates directly is not possible.
//

import XCTest
import SwiftUI
import WebKit
@testable import Today

@MainActor
final class WebViewNavigationPolicyTests: XCTestCase {

    // MARK: - Fixtures

    private let inMemoryDocument = URL(string: "about:blank")
    private let httpsLink = URL(string: "https://example.com/story")!
    private let localFile = URL(string: "file:///etc/passwd")!

    /// Every navigation type WebKit can report, so a new one is never silently permissive.
    private let allNavigationTypes: [WKNavigationType] = [
        .linkActivated, .formSubmitted, .backForward, .reload, .formResubmitted, .other
    ]

    // MARK: - Content WebViews: only the initial in-memory document may load

    /// The article / Reddit bodies are rendered with `loadHTMLString(_:baseURL: nil)`, which
    /// WebKit reports as an `.other` navigation to `about:blank`. That one must be allowed, or
    /// nothing renders at all.
    func testContentViewAllowsInitialInMemoryDocumentLoad() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: inMemoryDocument, isContentView: true),
            .allow,
            "The initial loadHTMLString navigation must be allowed"
        )
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: nil, isContentView: true),
            .allow,
            "A nil request URL is the same in-memory document"
        )
    }

    /// The core of the fix: a JS redirect / meta-refresh / iframe load is `.other`, and on a
    /// content view there is no legitimate one after the wrapper document.
    func testContentViewCancelsScriptInitiatedNavigation() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: URL(string: "https://evil.example/steal")!, isContentView: true),
            .cancel,
            "A simulated JS redirect must not be followed"
        )
    }

    func testContentViewCancelsFileURLForEveryNavigationType() {
        for type in allNavigationTypes {
            XCTAssertEqual(
                WebViewSecurity.policy(for: type, url: localFile, isContentView: true),
                .cancel,
                "file:// must be cancelled for navigation type \(type.rawValue)"
            )
            XCTAssertNil(
                WebViewSecurity.externalOpenURL(for: type, url: localFile, isContentView: true),
                "file:// must never be handed to an external open for navigation type \(type.rawValue)"
            )
        }
    }

    /// Deny by default: form posts, resubmits and back/forward on an in-memory document have no
    /// legitimate use here either.
    func testContentViewCancelsEveryNonInitialNavigationType() {
        for type in allNavigationTypes {
            XCTAssertEqual(
                WebViewSecurity.policy(for: type, url: httpsLink, isContentView: true),
                .cancel,
                "Content views navigate nowhere; navigation type \(type.rawValue) must be cancelled"
            )
        }
    }

    // MARK: - Content WebViews: embeds may load in a subframe

    /// `content:encoded` in ordinary feeds carries YouTube/Vimeo/Spotify iframes. Cancelling
    /// every non-initial navigation blanked all of them, so an http(s) *subframe* load is
    /// allowed — the framed page is cross-origin under its own CSP, and the article document
    /// around it still cannot script it.
    func testContentViewAllowsHTTPSSubframeLoadForEmbeds() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: httpsLink, isContentView: true, isSubframe: true),
            .allow,
            "an https iframe in an article body must load, or every embed renders blank"
        )
    }

    /// The concession is for frames only. Anything trying to navigate the article document
    /// itself stays cancelled, which is the property the whole policy exists for.
    func testContentViewStillCancelsMainFrameNavigation() {
        for type in allNavigationTypes {
            XCTAssertEqual(
                WebViewSecurity.policy(for: type, url: httpsLink, isContentView: true, isSubframe: false),
                .cancel,
                "main-frame navigation \(type.rawValue) must stay cancelled on a content view"
            )
        }
    }

    /// A subframe is not a blank cheque: the scheme allow-list still applies, so a framed
    /// `file://` cannot read the container.
    func testContentViewCancelsNonWebSubframeSchemes() {
        let nonWebURLs = [
            localFile,
            URL(string: "data:text/html,<h1>x</h1>")!,
            URL(string: "javascript:alert(1)")!,
        ]
        for url in nonWebURLs {
            XCTAssertEqual(
                WebViewSecurity.policy(for: .other, url: url, isContentView: true, isSubframe: true),
                .cancel,
                "\(url) must not load even as a subframe"
            )
        }
    }

    /// WebKit reports a new-window/popup navigation with a nil `targetFrame`, which the
    /// delegates map to `isSubframe == false` — so a popup cannot ride the embed exception.
    func testPopupNavigationIsNotTreatedAsASubframe() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: httpsLink, isContentView: true, isSubframe: false),
            .cancel,
            "a nil targetFrame is a popup, not a frame, and must stay cancelled"
        )
    }

    // MARK: - Content WebViews: link taps open externally, http(s) only

    func testLinkTapCancelsInPlaceAndSurfacesHTTPSURLForExternalOpen() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .linkActivated, url: httpsLink, isContentView: true),
            .cancel,
            "A tapped link must not navigate the content WebView itself"
        )
        XCTAssertEqual(
            WebViewSecurity.externalOpenURL(for: .linkActivated, url: httpsLink, isContentView: true),
            httpsLink,
            "…it must instead be surfaced for external opening"
        )
    }

    func testLinkTapToNonWebSchemeIsNotOpened() {
        for hostile in ["file:///etc/passwd", "data:text/html,<script>1</script>", "javascript:alert(1)", "today://settings", "ftp://example.com/x"] {
            let url = URL(string: hostile)
            XCTAssertNil(
                WebViewSecurity.externalOpenURL(for: .linkActivated, url: url, isContentView: true),
                "\(hostile) must not be opened externally"
            )
            XCTAssertEqual(
                WebViewSecurity.policy(for: .linkActivated, url: url, isContentView: true),
                .cancel,
                "\(hostile) must not be navigated to either"
            )
        }
    }

    /// Only link taps open externally. A script-driven navigation must not be turned into an
    /// external open — that would just move the redirect from the WebView to Safari.
    func testOnlyLinkTapsAreOpenedExternally() {
        for type in allNavigationTypes where type != .linkActivated {
            XCTAssertNil(
                WebViewSecurity.externalOpenURL(for: type, url: httpsLink, isContentView: true),
                "Navigation type \(type.rawValue) must not trigger an external open"
            )
        }
    }

    /// The in-app browser follows its own links; it must never also hand them to Safari.
    func testExternalSiteViewNeverOpensExternally() {
        for type in allNavigationTypes {
            XCTAssertNil(
                WebViewSecurity.externalOpenURL(for: type, url: httpsLink, isContentView: false),
                "Navigation type \(type.rawValue) on a browser view must be followed in place, not re-opened"
            )
        }
    }

    // MARK: - External-site WebViews: scheme check, not a blanket cancel

    /// `WebViewRepresentable` renders a genuine website with JavaScript on by design, so
    /// blanket-cancelling `.other` would break normal browsing. Its rule is the scheme check.
    func testExternalSiteViewAllowsHTTPAndHTTPSForEveryNavigationType() {
        for type in allNavigationTypes {
            for allowed in ["https://example.com/page", "http://example.com/page"] {
                XCTAssertEqual(
                    WebViewSecurity.policy(for: type, url: URL(string: allowed), isContentView: false),
                    .allow,
                    "\(allowed) must remain browsable for navigation type \(type.rawValue)"
                )
            }
        }
    }

    /// A JS-driven top-level navigation to `file://` after the initial page loads — the exact
    /// hole an absent `navigationDelegate` left open on this view.
    func testExternalSiteViewCancelsNonWebSchemes() {
        for hostile in ["file:///etc/passwd", "data:text/html,<script>1</script>", "today://settings", "ftp://example.com"] {
            XCTAssertEqual(
                WebViewSecurity.policy(for: .other, url: URL(string: hostile), isContentView: false),
                .cancel,
                "\(hostile) must be cancelled on the in-app browser"
            )
        }
    }

    /// `EmbeddedMediaWebView` wraps oEmbed markup with `loadHTMLString`, then the player iframe
    /// navigates to https. Both halves have to work.
    func testEmbeddedMediaWrapperAndItsPlayerFrameBothLoad() {
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: inMemoryDocument, isContentView: false),
            .allow,
            "The oEmbed wrapper document must still load"
        )
        XCTAssertEqual(
            WebViewSecurity.policy(for: .other, url: URL(string: "https://www.youtube.com/embed/abc"), isContentView: false),
            .allow,
            "The cross-origin player iframe must still load"
        )
    }

    // MARK: - The in-memory-document classifier

    func testInMemoryDocumentRecognisesOnlyAboutURLs() {
        XCTAssertTrue(WebViewSecurity.isInMemoryDocument(nil))
        XCTAssertTrue(WebViewSecurity.isInMemoryDocument(URL(string: "about:blank")))
        XCTAssertTrue(WebViewSecurity.isInMemoryDocument(URL(string: "about:srcdoc")))
        XCTAssertFalse(WebViewSecurity.isInMemoryDocument(URL(string: "https://example.com")))
        XCTAssertFalse(WebViewSecurity.isInMemoryDocument(URL(string: "file:///etc/passwd")))
        XCTAssertFalse(
            WebViewSecurity.isInMemoryDocument(URL(string: "https://about.example.com")),
            "Host-based lookalikes must not be mistaken for the in-memory document"
        )
    }

    // MARK: - The shared external-site delegate

    func testExternalSiteDelegateDefersToTheSharedPolicy() {
        let delegate = ExternalSiteNavigationDelegate()
        let webView = WKWebView(frame: .zero)

        // The delegate cannot be driven with a synthetic WKNavigationAction, so this asserts the
        // wiring instead: it is a WKNavigationDelegate and it installs on a WKWebView.
        webView.navigationDelegate = delegate
        XCTAssertTrue(webView.navigationDelegate === delegate)
    }

    // MARK: - Integration: no app-constructed WKWebView is left without a delegate

    #if os(iOS)
    /// Hosts every WebView-bearing SwiftUI view the app has and asserts that each `WKWebView`
    /// that actually gets built carries a `navigationDelegate`.
    ///
    /// This runs the real `makeUIView`, so a future view added without a delegate fails here as
    /// soon as it is listed. The macOS-only variants (`ScrollableWebView`, the AppKit halves of
    /// `WebViewWithHeight` / `PostWebView` / `CommentWebView` / `EmbeddedMediaWebView` /
    /// `ArticleWebView` / `SafariView`) cannot be hosted from this iOS test target; they are
    /// covered by the shared policy tests above and mirror the same wiring.
    func testEveryConstructedWebViewHasANavigationDelegate() throws {
        // A URL that resolves to nothing, so hosting these views starts no real network load.
        let url = URL(string: "https://unreachable.invalid/article")!

        let cases: [(String, AnyView)] = [
            ("WebViewRepresentable", AnyView(WebViewRepresentable(url: url))),
            ("ArticleWebView", AnyView(ArticleWebView(url: url))),
            ("WebViewWithHeight", AnyView(WebViewWithHeight(htmlContent: "<p>body</p>", height: .constant(0), selectedURL: .constant(nil)))),
            ("PostWebView", AnyView(PostWebView(html: "<p>selftext</p>", height: .constant(0), colorScheme: .light, accentColor: .orange, fontOption: .serif))),
            ("CommentWebView", AnyView(CommentWebView(html: "<p>comment</p>", height: .constant(0), colorScheme: .light, accentColor: .orange, fontOption: .serif))),
            ("EmbeddedMediaWebView", AnyView(EmbeddedMediaWebView(html: "<iframe src=\"https://unreachable.invalid/player\"></iframe>", colorScheme: .light)))
        ]

        for (name, view) in cases {
            let found = hostedWebViews(view)
            XCTAssertFalse(found.isEmpty, "\(name) built no WKWebView — the hosting harness needs updating, not the view")
            for webView in found {
                XCTAssertNotNil(
                    webView.navigationDelegate,
                    "\(name) constructs a WKWebView with no navigationDelegate — every navigation on it would be unchecked"
                )
            }
        }
    }

    /// Renders `view` in a real window long enough for SwiftUI to call `makeUIView`, then
    /// collects the WKWebViews it produced.
    private func hostedWebViews(_ view: AnyView) -> [WKWebView] {
        let host = UIHostingController(rootView: view.frame(width: 390, height: 800))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let found = descendantWebViews(of: host.view)

        window.isHidden = true
        window.rootViewController = nil
        return found
    }

    private func descendantWebViews(of view: UIView) -> [WKWebView] {
        var result: [WKWebView] = []
        if let webView = view as? WKWebView { result.append(webView) }
        for subview in view.subviews {
            result.append(contentsOf: descendantWebViews(of: subview))
        }
        return result
    }
    #endif
}
