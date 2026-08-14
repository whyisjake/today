---
title: "fix: Remediate security & systems audit findings"
type: fix
status: active
date: 2026-08-12
---

# fix: Remediate security & systems audit findings

## Summary

Remediate the findings from the zero-knowledge security and systems audit of the "Today" RSS reader, in four impact-ordered phases: (1) close the untrusted-HTML → WKWebView XSS surface and add a URL-scheme allow-list, (2) fix the three reliability criticals that break core behavior (permanent sync wedge, empty-feed-on-add, Stop-path crash) plus the zero-interaction memory-exhaustion vector, (3) harden the sync/persistence write path against duplicate/lost data and the migration crash-loop, and (4) clean up a set of high-value mediums (main-thread HTML importer, unbounded fetches, an AVPlayer leak, a formatter trap). Each behavior-bearing unit ships with tests, most driven through the existing `MockURLProtocol` harness.

---

## Problem Frame

Every feed a user subscribes to is fully attacker-controlled: the RSS/Atom/JSON/OPML body, Reddit user HTML, podcast MP3 bytes, and every URL therein. The audit found that untrusted feed HTML reaches `WKWebView.loadHTMLString` with JavaScript enabled and no sanitization (a working stored-XSS chain, defeated sanitizers via double entity-decode, and navigation delegates that allow any `.other` navigation including `file://`), that no URL-scheme allow-list exists anywhere (feed-controlled `file://`/app-scheme URLs are opened — a macOS sandbox pivot), and that several state-management defects silently corrupt or discard data: a background-launch path that permanently wedges all sync, newly added feeds that end up empty, a crash on the most common audio-Stop path, and unbounded downloads that let a hostile feed exhaust memory with zero interaction. The write path additionally mints duplicate articles/feeds under common conditions and has no versioned-schema migration, leaving upgraded stores unindexed and one schema change away from a launch crash-loop.

---

## Requirements

- R1. Untrusted feed/Reddit HTML rendered in any `WKWebView` cannot execute JavaScript, and a restrictive Content-Security-Policy is present on the rendered document.
- R2. HTML entity decoding is single-pass and correct; no code path double-decodes, and no ordering bug reconstructs escaped markup.
- R3. Navigation delegates do not allow cross-document navigation to arbitrary/`file://` URLs; link taps open only `http(s)` targets, externally.
- R4. No `openURL` / `UIApplication.open` / `NSWorkspace.open` / `webView.load(URLRequest)` / feed-ingestion path acts on a URL whose scheme is not on an explicit allow-list (`http`, `https`, plus intentional exceptions).
- R5. Background sync can never be permanently wedged; `isSyncInProgress` is released on every exit path.
- R6. Adding a feed persists the articles from the initial fetch; a newly added feed is never empty when its first fetch returned items.
- R7. Stopping audio never deallocates an `AVPlayer` with a live time observer (no AVFoundation exception).
- R8. No feed response or ID3 fetch buffers an unbounded body into memory; downloads are size-capped and validated before buffering.
- R9. Sync de-duplication is correct regardless of feed size (no failure at the SQLite bound-parameter limit) and never mass-inserts duplicates.
- R10. A per-feed save failure during sync does not poison the shared context or discard subsequent feeds' work, and a sync run that persisted nothing is not recorded as successful (so the next launch retries rather than being suppressed by the 2-hour window).
- R11. Possibly-deleted SwiftData objects are resolved by fetch-by-identifier, not `model(for:)`, on the sync and navigation paths.
- R12. A permanent-redirect URL rewrite is canonicalized and dup-checked; it cannot create duplicate feeds or non-canonical stored URLs.
- R13. The store has a versioned schema with an explicit migration plan; container-init failure degrades gracefully instead of `fatalError` crash-looping.
- R14. OPML sync has a reentrancy guard, advances HTTP validators only after the diff is applied, does not nil validators on a 304, and does not reactivate user-paused feeds.
- R15. Selected mediums are resolved: no main-thread WebKit HTML importer on list rows, bounded mark-all-read/migration fetches, no `AVPlayer`/observer leak in animated media, and no formatter trap on non-finite durations.

---

## Scope Boundaries

- Not fixing the full audio state machine beyond the Stop-path crash and the observer leak (interruption/route-change handling, TTS seek/progress races, cross-player remote-command collision, position-restore cross-episode seek) — tracked as follow-up.
- Not removing or rewriting the legacy `FeedManager.syncAllFeeds` pipeline wholesale; only the specific defects that are reachable (empty-feed-on-add, `model(for:)`, 301 rewrite) are fixed in place.
- Not implementing a general HTML sanitizer library; the XSS fix is defense-in-depth via disabling JS + CSP + navigation lockdown, not tag/attribute allow-listing.
- Not addressing the Low-severity tail from the audit (private-API `drawsBackground` KVC, control-char entities, OPML O(n²) rewrite, `isRedditFeed` dead property, `totalCountDescriptor` misdesign, etc.) except where a Phase-4 unit already touches the file.
- No new user-facing features; behavior changes are limited to correctness/security.

### Deferred to Follow-Up Work

- Audio subsystem hardening (interruption handling, seek/progress correctness, remote-command gating): separate plan.
- Backfill/migration cohort-skip and `deduplicateFeeds` destructiveness (canonical grouping, state merge): fold into the U-schema follow-up once a versioned migration exists.
- Low-severity tail cleanup: batched into a future "audit low findings" sweep.

---

## Context & Research

### Relevant Code and Patterns

- `Today/Views/ArticleDetailSimple.swift` — `createStyledHTML(...)`, `WebViewWithHeight` (iOS/macOS), `ScrollableWebView`, three `decidePolicyFor` handlers, `loadHTMLString(_, baseURL: nil)`.
- `Today/Views/RedditPostView.swift` — `PostWebView`, `CommentWebView`, `EmbeddedMediaWebView`, four `decidePolicyFor` handlers; `AnimatedMediaView` (AVPlayer + NotificationCenter observer); double `decodeHTMLEntities()` at the `updateUIView` seam.
- `Today/Utilities/HTMLHelper.swift` — `String` extension: `htmlToAttributedString` (WebKit importer), `decodeHTMLEntities`, `strippingHTML`, `htmlToPlainText`.
- `Today/Utilities/FeedURLNormalizer.swift` — `canonical`, `upgradingScheme`, `httpOnlyDomains`; the single choke point for feed-URL canonicalization.
- `Today/Models/Article.swift` — `articleURL` computed property (the feed-controlled link → URL sink).
- `Today/Services/ConditionalHTTPClient.swift` — `conditionalFetch`, `defaultSession`, `RedirectObserver`; `session.data(for:)` buffers the whole body.
- `Today/Services/BackgroundSyncActor.swift` — `insertArticlesInChunks` (GUID dedup fetch, per-feed `save`), 301 URL rewrite, `recordFeedHealth`.
- `Today/Services/BackgroundSyncManager.swift` — `performBackgroundSync` (the wedge), `handleBackgroundSync`.
- `Today/Services/FeedManager.swift` — `addFeed`, `syncFeed`, `syncFeedByID`, `fetchFeed` (304 handling pattern to mirror).
- `Today/Services/OPMLSubscriptionManager.swift` — `syncSubscription`, `syncAllSubscriptions`, `setFeedsActive`, validator handling.
- `Today/Services/ID3ChapterService.swift` — ranged GET header/tag fetch (unbounded buffer).
- `Today/Services/DatabaseMigration.swift` — one-shot migrations; unbounded main-actor fetches; flag-after-failed-save.
- `Today/Utilities/AudioFormatters.swift` — `formatDuration` (trapping `Int(...)`), `formatSpeed`.
- Tests: `TodayTests/*` is a **synchronized folder group** (new files auto-join the target). `ConditionalHTTPClientTests.swift` defines `MockURLProtocol` (per-URL delays, injectable). `SyncConcurrencyTests`, `SyncOutcomeTests`, `RedditJSONParserTests`, `HTMLHelperTests`, `PredicateCapabilityProbeTests` are the closest existing suites to extend.

### Institutional Learnings

- `Today/CLAUDE.md` "Concurrency" section: build settings `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` mean every unannotated declaration is main-actor isolated and `nonisolated async` runs on the caller's executor — only `@concurrent` forces the global executor. Any new background work must carry `@concurrent` and the `assert(!Thread.isMainThread)` guard used in `BackgroundFeedSync`.
- `Today/CLAUDE.md` "SwiftData constraints": `#Predicate` limits (no `lowercased()`; captured-array `contains` + `flatMap`/`??` fails at fetch time with an uncatchable ObjC exception; SQL NULL semantics differ from Swift optionals). `#Index` only applies to newly created stores. Prefer fetch-by-identifier over `context.model(for:)` for possibly-deleted objects — directly relevant to R11.
- `Today/CLAUDE.md` "Feed URLs": anything comparing a feed URL must canonicalize both sides through `FeedURLNormalizer` — directly relevant to R12.
- No `docs/solutions/` directory exists yet; a `ce-compound` capture is worth doing after this lands.

### External References

- Not required. The fixes follow platform-standard hardening (WKWebView JS disable + CSP, URL-scheme allow-list, SwiftData `VersionedSchema`/`SchemaMigrationPlan`, `URLSession` size limits) with strong local patterns already present.

---

## Key Technical Decisions

- **XSS fix is defense-in-depth, not sanitization.** Disable `allowsContentJavaScript` on every content web view, inject a restrictive CSP `<meta>` in the wrapper template, and make navigation delegates deny-by-default. This is robust against the double-decode bypass in a way HTML tag-stripping is not.
- **One shared scheme-allow-list utility.** Introduce a single `SafeURL`/scheme-guard helper used by every open/load/ingestion site, rather than scattered inline checks. Allow `http`/`https` for web content; preserve existing intentional exceptions (`FeedURLNormalizer.httpOnlyDomains`). Reddit/podcast deep-links stay `http(s)`-only through the UI.
- **Consolidate entity decoding.** Replace the four separate `decodeHTMLEntities` implementations (RSSParser, JSONFeedParser, RedditJSONParser, HTMLHelper) with the single correct `String.decodeHTMLEntities` in HTMLHelper, fix the ordering so `&amp;amp;` cannot chain into `&amp;lt;` within one pass, and delete every double-decode call site.
- **Empty-feed-on-add: insert, don't re-fetch.** `addFeed` should persist the articles it already parsed on the initial fetch (reuse the background insert path), and only then store validators — never immediately re-fetch with fresh validators.
- **Sync guard uses `defer`.** Release `isSyncInProgress` via a single `defer` at the top of the critical section so every early return (nil container included) resets it.
- **Dedup fetch is chunked.** Batch `parsedGUIDs` into sub-999 windows for the collision fetch; treat a fetch throw as "assume colliding / skip insert," never as "all new."
- **Versioned schema needs a real migration stage, and is the highest-risk unit in this plan.** Introduce `SchemaV1` (current on-disk shape) and `SchemaV2` (same shape with `#Index`), plus a `SchemaMigrationPlan` carrying an explicit `V1 → V2` stage. A single self-identical baseline would be a no-op migration that leaves existing stores unindexed, so it would not satisfy R13. Container init replaces `fatalError` with a recovery path that treats a version/migration mismatch as recoverable (never destructive) and reserves any store reset for genuinely unreadable stores behind an explicit guard — because this unit ships the versioned baseline and the recovery path together, a reset-on-any-failure default would silently destroy upgrading users' data.

---

## Open Questions

### Resolved During Planning

- *Disable JS globally or only on content views?* — Only on the feed/Reddit content web views (`allowsContentJavaScript = false`). The in-app full-page browser for user-tapped article links (`ArticleWebView` / short-article path) keeps JS but must still be scheme-guarded (R4) and is out of the XSS-content scope.
- *Sanitize vs. lock down?* — Lock down (JS off + CSP + nav deny-by-default). Resolved in Key Technical Decisions.
- *Where does ingestion scheme-validation live?* — In `FeedURLNormalizer.canonical` (reject non-`http(s)` before store/fetch) and at OPML `xmlUrl` intake, using the shared scheme-guard utility.

### Deferred to Implementation

- Exact `URLSession` size-capping mechanism (delegate-based `didReceive` byte counting vs. `Content-Length` precheck + bounded read) — decide against the real `MockURLProtocol` behavior during U9.
- Whether the container-init recovery should reset the store or surface a user-facing error state — decide when wiring `TodayApp` init against a deliberately-corrupt fixture store during U15.
- Whether `EmbeddedMediaWebView` can keep inline media with JS disabled, or needs a narrower allow (some oEmbed players require JS) — measure during U1; if a specific host needs JS, isolate it behind an explicit per-host opt-in rather than re-enabling globally.

---

## Implementation Units

### U1. Disable JavaScript and add CSP on all content WebViews

**Goal:** Untrusted feed/Reddit HTML can no longer execute JavaScript, and the rendered document carries a restrictive CSP. (R1)

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `Today/Views/ArticleDetailSimple.swift` (WebView configs + `createStyledHTML` template)
- Modify: `Today/Views/RedditPostView.swift` (`PostWebView`, `CommentWebView`, `EmbeddedMediaWebView` configs + `createStyledHTML`/wrapper templates)
- Test: `TodayTests/WebViewSecurityTests.swift` (new)

**Approach:**
- On each content `WKWebViewConfiguration`, set `defaultWebpagePreferences.allowsContentJavaScript = false`.
- In the shared HTML wrapper(s), inject `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src http: https: data:; style-src 'unsafe-inline'; media-src http: https:; font-src http: https: data:">` (no `script-src`; tune `img/media` to what content needs). Keep `baseURL: nil`.
- Re-check `EmbeddedMediaWebView`: if inline oEmbed players break with JS off, gate JS re-enable behind an explicit per-host opt-in (see Deferred).

**Patterns to follow:** existing `WebViewPool.makeConfiguration()` in `ArticleDetailSimple.swift`; keep the transparent-background setup intact.

**Test scenarios:**
- Happy path: a rendered document string produced by `createStyledHTML` contains the CSP `<meta>` and no enabling of JS.
- Edge case: config builder returns `allowsContentJavaScript == false` for every content web view factory.
- Error path (behavioral, via UI test or WebView eval harness if feasible): HTML containing `<script>window.__xss=1</script>` does not set `__xss` after load. If an on-device WebView test is not feasible in CI, assert the config/template invariants and document the manual verification step.

**Verification:** every content-view `WKWebViewConfiguration` disables content JS; the wrapper template emits the CSP; injected `<script>` does not execute.

---

### U2. Deny-by-default navigation delegates

**Goal:** Cross-document navigations (JS/meta/iframe, classified `.other`) are no longer unconditionally allowed; link taps open only `http(s)` targets externally. (R3)

**Requirements:** R3, R4

**Dependencies:** U3 (uses the scheme-guard utility)

**Files:**
- Modify: `Today/Views/ArticleDetailSimple.swift` (3 existing `decidePolicyFor` handlers on `ScrollableWebView`/`WebViewWithHeight`, **plus a new delegate on `WebViewRepresentable` — iOS and macOS variants, which today have none**)
- Modify: `Today/Views/RedditPostView.swift` (4 existing `decidePolicyFor` handlers, **plus `EmbeddedMediaWebView`, which also has none**)
- Test: `TodayTests/WebViewNavigationPolicyTests.swift` (new)

**Approach:**
- Replace the `if navigationType == .other { allow }` prefix with: allow only the initial in-memory document load (first `loadHTMLString`), and `.cancel` subsequent cross-document `.other` navigations.
- For `.linkActivated`, pass the URL through the scheme guard (U3) before handing to `openURL`/`NSWorkspace.open`; drop non-`http(s)`.
- Factor the shared policy into one helper so **all nine** handlers stay identical — the seven that exist today plus the two views that currently have no delegate at all.
- **`WebViewRepresentable` (the short-article "open in Today browser" path) and `EmbeddedMediaWebView` currently set no `navigationDelegate`.** `WebViewRepresentable` keeps JavaScript enabled by design (U1), and U3's scheme guard only validates the *initial* URL — so without a delegate, a JS redirect or in-page link on the live external page can navigate to `file://` or any scheme unchecked. These two views need a Coordinator wired up, not just an edit to an existing handler.
- For `WebViewRepresentable` specifically, the policy is stricter than "allow the first load": it renders a genuine external site, so subsequent top-level navigations must still be scheme-checked rather than blanket-cancelled (see Deferred question on whether to further restrict to the original host).

**Patterns to follow:** the existing `.linkActivated` branches already route to external open — keep that, just gate it. Mirror the existing `Coordinator: NSObject, WKNavigationDelegate` shape in `WebViewWithHeight` when adding delegates to the two views that lack one.

**Test scenarios:**
- Happy path: a `.linkActivated` to `https://example.com` → policy `.cancel` + external open invoked with that URL.
- Edge case: the first document load (`.other`, main frame, in-memory) is allowed.
- Error path: a `.other` navigation to `https://evil` (simulated JS redirect) → `.cancel`, no external open.
- Error path: a `.linkActivated`/`.other` to `file:///etc/passwd` → `.cancel`, not opened.
- Error path: on `WebViewRepresentable`, a JS-driven top-level navigation to `file:///etc/passwd` after the initial page loads → `.cancel`.
- Integration: every WKWebView the app constructs has a non-nil `navigationDelegate` (guards against a future view being added without one).

**Verification:** all nine handlers share one policy; no app-constructed WKWebView is left without a navigation delegate; the initial render is allowed, cross-document navigations are cancelled, and only `http(s)` links open externally.

---

### U3. URL scheme allow-list utility, applied everywhere

**Goal:** No feed-controlled URL is opened, loaded, or ingested unless its scheme is allow-listed. (R4)

**Requirements:** R4

**Dependencies:** None

**Files:**
- Create: `Today/Utilities/SafeURL.swift` (scheme-guard helper)
- Modify: `Today/Models/Article.swift` (`articleURL` gate)
- Modify: `Today/Views/ArticleDetailSimple.swift`, `Today/Views/RedditPostView.swift`, `Today/Views/TodayView.swift`, `Today/Views/NowPlayingView.swift`, `Today/ContentView.swift`, `Today/Views/ArticleWebView.swift` (open/load sites)
- Modify: `Today/Utilities/FeedURLNormalizer.swift` (reject non-`http(s)` at canonicalization)
- Modify: `Today/Services/OPMLSubscriptionManager.swift` (guard OPML `xmlUrl` intake)
- Test: `TodayTests/SafeURLTests.swift` (new); extend `TodayTests/OPMLDiffTests.swift`

**Approach:**
- `SafeURL.webOpenable(_ string:) -> URL?` returns a URL only for `http`/`https` (respecting `FeedURLNormalizer.httpOnlyDomains` for the http exception). All open sites and `webView.load(URLRequest:)` for feed content route through it.
- `articleURL` returns nil for non-allow-listed schemes.
- `FeedURLNormalizer.canonical` returns nil / rejects non-`http(s)` input so `file://`/`data://` `xmlUrl` never gets stored or fetched.

**Patterns to follow:** `FeedURLNormalizer` is already the single canonicalization choke point — extend it, don't scatter checks.

**Test scenarios:**
- Happy path: `https://x/feed` and an `httpOnlyDomains` host over `http://` pass.
- Edge case: empty string, missing scheme, uppercase `HTTP://`.
- Error path: `file://`, `data:`, `javascript:`, `ftp://`, `tel:`, `facetime:` all rejected (nil).
- Integration: an OPML entry with `xmlUrl="file:///…"` is dropped during import (extend `OPMLDiffTests`).

**Verification:** every open/load/ingestion site rejects non-allow-listed schemes; malicious `xmlUrl` never reaches `URLSession`.

---

### U4. Consolidate and fix HTML entity decoding

**Goal:** Single correct entity decoder; no double-decode and no ordering bug that reconstructs escaped markup. (R2)

**Requirements:** R2

**Dependencies:** None

**Files:**
- Modify: `Today/Utilities/HTMLHelper.swift` (canonical `String.decodeHTMLEntities`, fix ordering)
- Modify: `Today/Services/RSSParser.swift`, `Today/Services/JSONFeedParser.swift`, `Today/Services/RedditJSONParser.swift` (delete local impls, call the canonical one)
- Modify: `Today/Views/RedditPostView.swift` (remove `.decodeHTMLEntities().decodeHTMLEntities()` double call)
- Test: extend `TodayTests/HTMLHelperTests.swift`, `TodayTests/RedditJSONParserTests.swift`

**Approach:**
- Fix ordering so numeric/`&amp;`-last resolution cannot chain (`&amp;amp;lt;` must decode to the literal text `&lt;`, not to `<`).
- Replace the four implementations with one; call sites decode exactly once.

**Execution note:** Add characterization tests capturing current decoder output on representative feed strings before consolidating, so the merge is provably behavior-preserving except for the intended ordering/double-decode fix.

**Test scenarios:**
- Happy path: `&amp;`, `&lt;`, `&#8217;`, `&quot;` decode correctly, once.
- Edge case: `&amp;amp;lt;` → `&lt;` (literal), NOT `<`.
- Error path: `&amp;amp;lt;script&amp;amp;gt;` never yields an executable `<script>` after one decode.
- Integration: Reddit `selftext_html` no longer double-decoded at the `PostWebView` seam (assert single decode).

**Verification:** one decoder remains; the smuggling inputs stay inert; existing decode tests still pass.

---

### U5. Fix the background-sync wedge

**Goal:** `isSyncInProgress` is released on every exit path; a nil container (background launch) can never permanently disable sync. (R5)

**Requirements:** R5

**Dependencies:** None

**Files:**
- Modify: `Today/Services/BackgroundSyncManager.swift` (`performBackgroundSync`)
- Test: `TodayTests/BackgroundSyncManagerTests.swift` (new)

**Approach:**
- Acquire the flag, then `defer { Task { @MainActor in isSyncInProgress = false } }` (or restructure so the nil-container guard returns before the flag is set). Ensure the reset is on the same actor and runs for the nil-container return, the empty-feeds return, and normal completion.

**Test scenarios:**
- Happy path: a completed sync leaves `isSyncInProgress == false`.
- Edge case: `performBackgroundSync` with `modelContainer == nil` returns and leaves `isSyncInProgress == false`, and a subsequent sync with a container set proceeds.
- Error path: a sync whose inner work throws/cancels still resets the flag.
- Integration: two rapid `triggerManualSync()` calls — the second no-ops while the first runs, and the flag is false afterward.

**Verification:** no exit path leaves the flag set; a nil-container early return does not disable future syncs.

---

### U6. Fix empty-feed-on-add

**Goal:** Adding a feed persists the articles from the initial fetch; a newly added feed is never empty when its first fetch returned items. (R6)

**Requirements:** R6

**Dependencies:** U12 (canonicalization of the redirect target — see Approach)

**Files:**
- Modify: `Today/Services/FeedManager.swift` (`addFeed`; **plus session injection — see below**)
- Test: `TodayTests/FeedManagerAddFeedTests.swift` (new), using `MockURLProtocol`

**Approach:**
- Stop discarding the parsed articles from the initial fetch. Insert them via **`updateFeedWithArticles` on the same main context** — named explicitly rather than left open, because the background `insertArticlesInChunks` path runs on a separate context with different isolation and also rewrites `feed.url`; wiring that into the `@MainActor` `addFeed` would risk the cross-context duplicates U9/U12 exist to prevent. Note `updateFeedWithArticles` does not rewrite `feed.url`, so `addFeed`'s `actualURL` handling still owns the redirect case.
- Then store validators. Do not immediately call `syncFeed` with the just-stored validators (which 304s and inserts nothing).
- **Session injection (prerequisite for the tests below).** `FeedManager.addFeed → fetchFeed → conditionalFetch` currently takes no `URLSession` and always uses `ConditionalHTTPClient.defaultSession`; `MockURLProtocol` is only ever wired through `config.protocolClasses` on a caller-supplied session, so as written these tests would hit the real network. Thread an optional `URLSession` through `FeedManager.init`/`addFeed`/`fetchFeed` and forward it to `conditionalFetch(session:)`, mirroring the existing injectable `session: URLSession = ConditionalHTTPClient.defaultSession` parameter on `BackgroundFeedSync`.
- **Redirect canonicalization.** `addFeed` currently sets `actualURL = finalURL?.absoluteString ?? feedURL` with no `FeedURLNormalizer.canonical` pass — the same defect U12 fixes on the sync path. Apply canonicalization here too so the redirect edge case below is satisfiable in this unit rather than being reintroduced and re-fixed in Phase 3.

**Execution note:** Test-first — write the failing "add feed on an ETag-honoring mock server yields N articles" test before changing `addFeed`. The session-injection change lands first, since the test cannot be written without it.

**Test scenarios:**
- Happy path: `MockURLProtocol` returns a 3-item feed with an `ETag`; after `addFeed`, the feed has 3 articles.
- Edge case: a permanent redirect on the initial fetch still stores canonical URL and inserts articles once (no duplicate).
- Error path: initial fetch returns 0 items → feed added, 0 articles, no crash.
- Integration: adding then immediately syncing again (304) does not delete or duplicate the initial articles.

**Verification:** a newly added feed shows its initial articles on an ETag/Last-Modified-honoring server.

---

### U7. Fix the Stop-path player crash

**Goal:** Stopping audio removes observers before releasing the `AVPlayer`; no AVFoundation "deallocated while observer registered" exception. (R7)

**Requirements:** R7

**Dependencies:** None

**Files:**
- Modify: `Today/Services/PodcastAudioPlayer.swift` (`stop()`, `removePlayerObservers()`)
- Test: `TodayTests/PodcastAudioPlayerTests.swift` (new)

**Approach:**
- Reorder `stop()` to call `removePlayerObservers()` (and remove the periodic time observer via the retained token) **before** `player = nil`. Audit `pause()`/replace/`deinit` for the same ordering.

**Test scenarios:**
- Happy path: play → stop leaves `player == nil`, `isPlaying == false`, and the time-observer token cleared, with no exception.
- Edge case: stop called with no active player is a safe no-op.
- Edge case: article switch (play A → play B) tears down A's observer before B's player is installed.

**Verification:** the observer is removed before the player is released on every teardown path.

---

### U8. Response-size caps on downloads

**Goal:** No feed response or ID3 fetch buffers an unbounded body; downloads are validated and size-capped. (R8)

**Requirements:** R8

**Dependencies:** None

**Files:**
- Modify: `Today/Services/ConditionalHTTPClient.swift` (`conditionalFetch` / `defaultSession`)
- Modify: `Today/Services/ID3ChapterService.swift` (**replace `URLSession.shared` with an injectable session**; bounded read; validate `206`)
- Test: extend `TodayTests/ConditionalHTTPClientTests.swift`; add `TodayTests/ID3ChapterServiceTests.swift`

**Approach:**
- Cap the feed body at a sane maximum (e.g. a few MB); enforce via delegate byte-counting or a `Content-Length` precheck + bounded read (decide in-implementation against `MockURLProtocol`). Exceeding the cap throws a typed error handled as a per-feed failure.
- In `ID3ChapterService`, **the cap must be enforced during transfer, not after it.** `session.data(for:)` only returns once the entire body is already resident, so checking `statusCode == 206` afterward cannot prevent the exhaustion this unit targets — the memory is already gone. Use a streaming/bounded read (e.g. `bytes(for:)` with a running byte count, or a delegate that cancels the task) that aborts as soon as the cap is exceeded or the response is not `206`.
- **`ID3ChapterService` currently uses `URLSession.shared`, which silently ignores registered mock protocols** (documented in `ConditionalHTTPClient`'s own comments), so the tests below are unwritable until it takes an injectable session. Add one, defaulting to the timeout-configured session, mirroring `BackgroundFeedSync`'s parameter.

**Test scenarios:**
- Happy path: a normal-size feed fetches fine; a valid `206` ID3 range parses.
- Edge case: body exactly at the cap succeeds; one byte over throws the typed error.
- Error path: a server ignoring `Range` (returns `200` + full body) is rejected by `ID3ChapterService` without buffering the whole file.
- Integration: an oversized feed surfaces as a per-feed failure in the sync results, not an app crash (extend sync tests).

**Verification:** oversized responses throw before exhausting memory; ID3 only parses validated `206` ranges.

---

### U9. Chunk GUID dedup fetch under the SQLite bound-parameter limit

**Goal:** Sync de-duplication is correct regardless of feed size; a large feed never mass-inserts duplicates. (R9)

**Requirements:** R9

**Dependencies:** None

**Files:**
- Modify: `Today/Services/BackgroundSyncActor.swift` (`insertArticlesInChunks` collision fetch)
- Test: extend `TodayTests/SyncOutcomeTests.swift`

**Approach:**
- Batch `parsedGUIDs` into windows below the SQLite bound-parameter limit (≤ ~900) and union the collision results. On a fetch throw, treat the batch as "cannot confirm new" and skip inserting those (conservative), logging the anomaly — never fall through to "all new."

**Test scenarios:**
- Happy path: a 50-item feed dedups correctly (re-sync inserts nothing new).
- Edge case: a > 1000-item response dedups without a fetch failure; a second sync inserts zero duplicates.
- Error path: a forced collision-fetch failure does not mass-insert; it skips and logs.

**Verification:** re-syncing a > 1000-item feed produces no duplicate articles.

---

### U10. Rollback on save failure, and honest sync-success reporting

**Goal:** A per-feed save failure does not poison the shared context or discard later feeds' work, **and a run that persisted nothing is not recorded as a successful sync.** (R10)

**Requirements:** R10

**Dependencies:** None

**Files:**
- Modify: `Today/Services/BackgroundSyncActor.swift` (`save(_:label:)`, `insertArticlesInChunks`, `syncAllFeeds`'s last-sync-date gate)
- Test: extend `TodayTests/SyncOutcomeTests.swift`

**Approach:**
- On a failed `context.save()`, call `context.rollback()` before continuing, so the poisoned pending changes don't cascade into every subsequent feed's save. Because saves are already per-feed, the only unsaved changes at failure time belong to the feed that just failed — rollback is correctly scoped to it.
- **Make save failure observable to the caller.** `save(_:label:)` currently returns `Void` and swallows the error in a `do/catch`, so nothing upstream can tell a fully-failed run from a successful one. Change it to report success (return `Bool`, or throw and let the loop catch), and aggregate the per-feed results into an insert-phase outcome — a small `Sendable` struct in the shape of the existing `FetchPhaseResults`, carrying persisted/failed counts and an `anyPersisted` flag. `insertArticlesInChunks` returns it instead of `Void`.
- **Gate the sync date on persistence, not just on fetching.** `hadAnySuccess` is computed purely from the fetch phase (`!parsed.isEmpty`), so today `lastGlobalSyncDate` is stamped even when every save failed — and `needsSync()`'s 2-hour window then suppresses the retry, which is precisely the "stale content labelled freshly synced" failure the audit found. The gate becomes fetch-success **and** insert-success: stamp the date only when at least one feed both responded and persisted.
- A 304 counts as persisted when its `lastFetched` save succeeds — an all-304 run is a legitimately successful sync and must still stamp the date.
- **Per-feed `ModelContext` isolation is explicitly not adopted.** Considered and rejected: with per-feed saves plus rollback, a failure is already contained, so a fresh context per feed adds allocation and loses the warm registered-object cache without buying additional correctness. Recorded here so the next reader doesn't re-litigate it. (The context does accumulate registered objects across a long sync — a memory-growth concern, not a correctness one; out of scope for this plan.)

**Patterns to follow:** `FetchPhaseResults` in the same file — a `Sendable` struct carrying successes and failures with a derived convenience flag — is the shape the insert-phase outcome should mirror.

**Test scenarios:**
- Happy path: three feeds insert; all persist; `lastGlobalSyncDate` is stamped.
- Error path: feed 1's save fails → feed 1 is rolled back, feeds 2–3 still persist, and the date is still stamped (partial success is success).
- Error path: every feed's save fails → `anyPersisted == false`, `lastGlobalSyncDate` is NOT stamped, and the failure is logged.
- Edge case: an all-304 run (nothing to insert, `lastFetched` saves succeed) counts as persisted and stamps the date.
- Edge case: zero feeds responded (all fetches failed) → date not stamped, matching existing behavior.
- Integration: after a fully-failed run, `FeedManager.needsSync()` returns true immediately rather than suppressing the retry for two hours.

**Verification:** one feed's save failure no longer discards subsequent feeds' work; the last-sync date is written only when something actually reached disk; a fully-failed run is retried on the next launch instead of being suppressed for two hours.

---

### U11. Replace `model(for:)` with fetch-by-identifier

**Goal:** Possibly-deleted objects are resolved by fetch-by-identifier on the sync and navigation paths. (R11)

**Requirements:** R11

**Dependencies:** None

**Files:**
- Modify: `Today/Services/FeedManager.swift` (`syncFeedByID`)
- Modify: `Today/Views/TodayView.swift`, `Today/Views/FeedListView.swift` (navigation destinations)
- Test: extend `TodayTests/FeedListQueryTests.swift` / add targeted tests

**Approach:**
- Replace `context.model(for:) as? Feed/Article` with a `FetchDescriptor` by `persistentModelID` (the pattern already used in `BackgroundSyncActor.insertArticlesInChunks`), so a deleted object is a clean miss rather than a stub that resurrects or throws.

**Patterns to follow:** the fetch-by-identifier block in `BackgroundSyncActor.insertArticlesInChunks`.

**Test scenarios:**
- Happy path: resolving a live feed/article by id returns it.
- Edge case: resolving a deleted id returns nil (no stub, no resurrection).
- Integration: deleting a feed mid-sync causes its results to be skipped, not re-inserted against a zombie feed.

**Verification:** deleted-object resolution is a clean miss on the sync and nav paths.

---

### U12. Canonicalize and dup-check permanent-redirect URL rewrites

**Goal:** A 301/308 URL rewrite is canonicalized and dup-checked; it cannot create duplicate feeds or non-canonical stored URLs. (R12)

**Requirements:** R12

**Dependencies:** U3 (scheme guard), shares `FeedURLNormalizer`

**Files:**
- Modify: `Today/Services/BackgroundSyncActor.swift` (redirect rewrite in `insertArticlesInChunks`)
- Modify: `Today/Services/FeedManager.swift` (redirect rewrite paths)
- Modify: `Today/Services/ConditionalHTTPClient.swift` (only treat a redirect as permanent when the final hop is permanent, not any hop)
- Test: extend `TodayTests/ConditionalHTTPClientTests.swift`, `TodayTests/SyncOutcomeTests.swift`

**Approach:**
- Before assigning `feed.url = newURL`, run it through `FeedURLNormalizer.canonical` and check no other feed already holds that URL; if one does, do not create/rewrite into a duplicate (leave as-is or merge-skip).
- Tighten `hadPermanentRedirect` so a mixed `301→302→…` chain does not rewrite to a temporary endpoint.
- The `FeedManager` redirect-path tests depend on the injectable `URLSession` added in U6; if U6 has not landed, that change comes first here.

**Test scenarios:**
- Happy path: a clean 301 to a new canonical URL rewrites once.
- Edge case: 301 to an `http://`/Reddit-non-`.json` target is canonicalized before storage.
- Error path: 301 whose target equals an existing feed's URL does not create a duplicate.
- Edge case: `301→302→CDN` does not rewrite the stored URL to the temporary CDN.

**Verification:** redirect rewrites are canonical, deduped, and only for genuinely-permanent final destinations.

---

### U13. OPML sync correctness

**Goal:** OPML sync has a reentrancy guard, advances validators only after applying the diff, does not nil validators on 304, and does not reactivate user-paused feeds. (R14)

**Requirements:** R14

**Dependencies:** U11 (fetch-by-id), U12 (canonicalization)

**Files:**
- Modify: `Today/Services/OPMLSubscriptionManager.swift` (`syncSubscription`, `setFeedsActive`, validator handling, 304 path)
- Test: extend `TodayTests/OPMLDiffTests.swift`; add `TodayTests/OPMLSubscriptionSyncTests.swift`

**Approach:**
- Add a reentrancy guard that actually gates (shared/static or injected, not a fresh-per-instance flag).
- Persist `httpEtag`/`httpLastModified`/`lastFetched` only after the add/deactivate diff has been applied and saved.
- On a 304, keep the previously stored validators (echo input) rather than overwriting with the 304 response's (often nil) values — mirror `FeedManager.fetchFeed`'s 304 handling.
- Distinguish user-paused feeds from sync-deactivated feeds so reactivation only targets the latter (e.g., a `deactivatedBySync` marker).
- `OPMLSubscriptionManager` also calls `conditionalFetch` with no session argument. Either scope the tests to diff/validator logic that needs no live fetch, or thread an injectable session through as U6 does for `FeedManager` — decide when writing the tests, but do not assume `MockURLProtocol` works against the default session.

**Test scenarios:**
- Happy path: a changed OPML applies adds/removes and only then advances validators.
- Edge case: a 304 OPML fetch preserves stored validators (does not nil them).
- Error path: a failure mid-apply does not advance validators (next sync retries).
- Integration: a user-paused managed feed stays paused across an OPML sync; a sync-deactivated feed can be reactivated.
- Edge case: two concurrent OPML syncs — the second no-ops via the guard.

**Verification:** validators advance only post-apply, survive 304s, and user pauses are respected.

---

### U14. Versioned schema, migration plan, and graceful container init

**Goal:** The store has a versioned schema with an explicit migration plan; container-init failure degrades gracefully instead of `fatalError` crash-looping. (R13)

**Requirements:** R13

**Dependencies:** None

**Files:**
- Create: `Today/Models/TodaySchema.swift` (`VersionedSchema` + `SchemaMigrationPlan`)
- Modify: `Today/TodayApp.swift` (`sharedModelContainer` init: use the migration plan; recover instead of `fatalError`)
- Test: extend `TodayTests/ModelSchemaTests.swift` (open a prior-schema fixture store, then the current schema)

**Approach:**
- Define **two** versions, not one: `SchemaV1` wrapping the current `Feed`/`Article`/`OPMLSubscription` shape as it exists on disk today, and `SchemaV2` as the current shape *with* the `#Index` declarations. Add a `SchemaMigrationPlan` with an explicit `V1 → V2` stage.
  - **A single self-identical baseline is a no-op and does not satisfy R13.** SwiftData sees no version transition and rebuilds nothing, so existing users stay unindexed — the exact problem this unit exists to fix. Only a real stage (lightweight if it suffices, custom if it does not) causes the store to rebuild and materialize the indexes.
- Replace `fatalError` on container creation with a recovery path that **distinguishes failure kinds**:
  - A schema-version or migration mismatch is *recoverable* — retry/migrate, or surface an error state. It must **never** reset the store.
  - Only a genuinely unreadable/corrupt store may take a destructive last-resort path, and that path is gated behind an explicit guard (and ideally a backup of the existing store file first).
  - Rationale: this unit introduces the versioned baseline *and* the recovery path together. If the baseline's schema identity does not match what SwiftData recorded for an existing store, init throws and lands in the new recovery path — a reset-on-any-failure default would silently destroy every upgrading user's data.

**Execution note:** Characterization-first, and the fixture matters. Add a test that opens a store **created by the current shipping (pre-versioned) code** — not one freshly created by the new versioned container — and confirms it opens and retains its rows before changing `TodayApp` init. A test written against a fresh store passes while real upgrades fail.

**Test scenarios:**
- Happy path: fresh store opens under the versioned container.
- Edge case: a store created under the pre-versioned schema opens under the new migration plan with all Feed/Article/OPMLSubscription rows intact (assert counts, not just that it opens).
- Edge case: after migrating a pre-existing unindexed store, `sqlite_master` contains the `Z_Article_SwiftDataIndex*` entries — i.e. the indexes were actually created, not merely declared.
- Error path: a schema/migration mismatch does NOT reset the store; it surfaces an error or retries.
- Error path: a deliberately-corrupt store does not crash-loop; init takes the guarded recovery path.

**Verification:** a pre-existing store migrates with rows intact and indexes present in `sqlite_master`; init never `fatalError`s; no failure mode short of genuine corruption can delete user data.

---

### U15. Remove main-thread WebKit HTML importer from list rows

**Goal:** List rows never run the synchronous `NSAttributedString(.html)` WebKit importer (a main-thread hang + SSRF/IP-leak beacon). (R15)

**Requirements:** R15

**Dependencies:** None

**Files:**
- Modify: `Today/Utilities/HTMLHelper.swift` (`htmlToAttributedString` usage)
- Modify: `Today/Views/TodayView.swift`, `Today/Views/ArticleWebView.swift` (row description rendering)
- Test: extend `TodayTests/HTMLHelperTests.swift`

**Approach:**
- Render row descriptions from the already-precomputed `plainTextDescription` (or a lightweight inline-markup path), not the WebKit HTML importer. Keep `htmlToAttributedString` only where a full attributed render is genuinely needed off the hot path, or remove it if unused after the change.

**Test scenarios:**
- Happy path: a row description with `<em>`/entities renders as expected plain/inline text without invoking the HTML importer.
- Error path: a description containing `<img src=http://tracker>` produces no network request during row rendering.

**Verification:** scrolling the list issues no WebKit-importer network requests and does not call the `.html` importer per row.

---

### U16. Bound mark-all-read and migration fetches

**Goal:** Mark-all-read and the migration fetches are bounded, not whole-table main-actor materializations. (R15)

**Requirements:** R15

**Dependencies:** None

**Files:**
- Modify: `Today/Views/TodayView.swift` (`markAllAsRead`), `Today/TodayApp.swift` (`markAllArticlesAsRead`)
- Modify: `Today/Services/DatabaseMigration.swift` (unbounded fetches; flag-after-failed-save)
- Test: extend `TodayTests/ArticleQueryTests.swift` / add migration tests

**Approach:**
- Use a category-scoped predicate + windowed/batched updates for mark-all-read instead of fetching the entire unread table and filtering in Swift.
- Bound the migration fetches (predicate + `fetchLimit`, batched cursor as the backfill already does) and only set the completion flag after a successful save.

**Test scenarios:**
- Happy path: mark-all-read for a category marks only that category, in bounded batches.
- Edge case: a large unread set is processed without a single whole-table fetch.
- Error path: a migration whose save fails does not set its completion flag (retries next launch).

**Verification:** no unbounded main-actor Article fetch remains on these paths; migration flags are save-gated.

---

### U17. Fix AVPlayer observer leak and the formatter trap

**Goal:** Animated media does not leak an `AVPlayer`/observer; `formatDuration` cannot trap on non-finite input. (R15)

**Requirements:** R15

**Dependencies:** None

**Files:**
- Modify: `Today/Views/RedditPostView.swift` (`AnimatedMediaView` — remove the NotificationCenter observer on disappear)
- Modify: `Today/Utilities/AudioFormatters.swift` (`formatDuration` finite-guard; `formatSpeed` precision)
- Test: add `TodayTests/AudioFormattersTests.swift`

**Approach:**
- In `AnimatedMediaView.onDisappear`, call `NotificationCenter.default.removeObserver` for the token (store the returned observer) in addition to invalidating the time observer and niling the player.
- Guard `formatDuration` with `isFinite` (return a safe placeholder for `nan`/`inf`/out-of-range) before the trapping `Int(...)`. Fix `formatSpeed` to show the selected value (e.g., 1.25 → "1.25x") rather than `%.2g`.

**Test scenarios:**
- Happy path: `formatDuration(3661)` → "1:01:01"; `formatSpeed(1.25)` → "1.25x".
- Edge case: `formatDuration(.nan)`, `.infinity`, and a value ≥ 2⁶³ return a safe placeholder, no crash.
- Integration (leak): scrolling `AnimatedMediaView` in/out removes its observer (assert observer count / no retained player via a test seam).

**Verification:** the animated-media observer is removed on disappear; non-finite durations never crash the formatter.

---

## System-Wide Impact

- **Interaction graph:** WebView navigation delegates (U1–U3), the sync pipeline (`BackgroundFeedSync` + `FeedManager` + `OPMLSubscriptionManager`, U5/U6/U9–U13), SwiftData container init and migrations (U14/U16), and audio teardown (U7/U17). The scheme-guard utility (U3) is a new shared dependency touched by many view files.
- **Error propagation:** oversized-download and parse failures must surface as per-feed failures (recorded via `recordFeedHealth`), never as crashes; container-init failure must degrade, not `fatalError`. Persistence failures must propagate too — U10 changes `save` from a silent `Void` to a reported outcome, so "did anything reach disk?" becomes answerable upstream and the sync date stops lying.
- **State lifecycle risks:** the sync-flag reset (U5), save-rollback (U10), and validator-advance ordering (U13) all guard against partial/poisoned state; U6 and U12 guard against duplicate rows.
- **API surface parity:** the entity decoder (U4) and scheme guard (U3) must be applied at *every* call site, not just the audited ones — grep for all `decodeHTMLEntities`, `openURL`, `.open(`, and `loadHTMLString` uses before closing each unit. The same applies to WebView construction: every `WKWebView(frame:configuration:)` site must end up with a navigation delegate, including the two views that have none today.
- **Testability prerequisite (cuts across U6, U8, U12, U13):** only `BackgroundFeedSync` currently takes an injectable `URLSession`. `FeedManager`, `OPMLSubscriptionManager`, and `ID3ChapterService` all reach the network through the default or shared session, which silently ignores `MockURLProtocol`. Each of those units must add session injection before its tests can be written; treat that as part of the unit, not a separate refactor.
- **Integration coverage:** most units need `MockURLProtocol`-driven tests exercising the real fetch→parse→insert chain, not mocked layers.
- **Unchanged invariants:** the read-path `ArticleQuery` semantics, the `@concurrent` background-isolation discipline, and the transparent-WebView styling are not changed; new work must preserve them (any new background function carries `@concurrent` + the main-thread assert).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Disabling JS breaks legitimate embedded media (oEmbed players) | Measure in U1; isolate any genuine need behind an explicit per-host opt-in rather than global re-enable |
| Disabling JS breaks WebView height measurement (content views size via `evaluateJavaScript("…scrollHeight")`) → blank/clipped articles | Verify in U1 that app-initiated `evaluateJavaScript` still returns a height with content JS disabled and the CSP present; if not, move height reporting to a `WKUserScript`/navigation-based mechanism *before* disabling JS |
| **Versioned-schema migration mishandles existing stores → total data loss** | Two-version schema with a real `V1 → V2` stage; recovery path treats version/migration mismatch as recoverable and never resets; destructive reset reserved for genuinely corrupt stores behind an explicit guard; characterization test must open a store created by the *current shipping build*, not a freshly-created one (U14) |
| Single-version baseline ships as a no-op → upgraded stores stay unindexed while the plan claims R13 is met | U14 asserts `sqlite_master` contains the index entries after migrating a pre-existing unindexed fixture store — opening successfully is not sufficient evidence |
| Entity-decoder consolidation changes rendering subtly | Characterization tests capture current output before merge (U4) |
| Size-cap false-positives reject valid large feeds | Cap set generously (several MB); exceeding it is a per-feed failure, not a hard error, and is logged |
| Scheme guard over-blocks a scheme users rely on (e.g., `mailto:` in article bodies) | Allow-list is explicit and reviewable; add intentional exceptions consciously, default-deny |
| Build settings (`MainActor` default isolation) reintroduce main-thread work in new code | Every new background function carries `@concurrent` + `assert(!Thread.isMainThread)` per `CLAUDE.md` |

---

## Phased Delivery

### Phase 1 — Security (U3, U1, U2, U4, U15)
Close the XSS surface, lock down navigation, add the scheme allow-list, fix entity decoding, and remove the main-thread HTML importer. Highest real-world risk; largely self-contained. Land in listed order: U3 ships the scheme-guard utility that U2's navigation delegates consume.

### Phase 2 — Reliability criticals (U5, U12, U6, U7, U8)
Sync wedge, redirect canonicalization, empty-feed-on-add, Stop-path crash, and download size caps. High user-visible impact, low blast radius. Land in listed order: **U12 moves up from Phase 3 because U6 depends on it** — `addFeed`'s redirect edge case cannot store a canonical URL until canonicalization exists, and doing it twice would mean hand-rolling in Phase 2 what Phase 3 reimplements. U6 and U8 each begin with the session-injection change their tests require.

### Phase 3 — Write-path hardening (U9, U10, U11, U13, U14)
Dedup chunking, save-rollback, fetch-by-identifier, OPML correctness, and the versioned schema. Land in listed order — U11 (and U12, from Phase 2) feed U13. **U14 lands last and is the highest-risk unit in the plan**: it is the only one that can destroy existing user data, so it should land on its own, after the rest of the phase is green.

### Phase 4 — Selected mediums (U16, U17)
Bounded fetches, observer leak, formatter trap. Independent; can land anytime.

---

## Sources & References

- Origin: in-conversation security & systems audit (2026-08-12), covering `Today/Views/*`, `Today/Services/*`, `Today/Utilities/*`, `Today/Models/*`.
- Conventions: `Today/CLAUDE.md` (Concurrency, SwiftData constraints, Feed URLs, Tests sections).
- Test harness: `TodayTests/ConditionalHTTPClientTests.swift` (`MockURLProtocol`), `SyncConcurrencyTests.swift`, `SyncOutcomeTests.swift`, `PredicateCapabilityProbeTests.swift`.
