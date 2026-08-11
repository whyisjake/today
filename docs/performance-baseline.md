# Performance baseline

Reference measurements for `docs/plans/2026-08-11-003-fix-startup-and-sync-performance-plan.md`.
Captured after U1 (signpost instrumentation), before any read-path or sync-path change.

Every later performance claim in that plan is measured against these numbers. Re-run the
harness below after each unit and compare.

## Environment

| | |
|---|---|
| Device | iPhone 17 simulator, iOS 18 |
| Build | Debug (`xcodebuild -scheme Today -configuration Debug`) |
| Store | 10,358 articles / 31 feeds, `default.store` 6.0 MB |
| Commit | `2fa036c` (U1 instrumentation) |

Simulator Debug numbers are not device numbers — they are useful as a *relative* reference,
which is what regression detection needs. Absolute targets should be re-measured on device.

## Launch

| Phase | Measured | Notes |
|---|---|---|
| `app-init` | 265–311 ms (4 runs: 266.9, 265.5, 311.3, 273.4) | Audio session setup + background task registration + `ModelContainer` creation |
| `default-feed-setup` | 92–266 ms | Early-return path — feeds already exist, so this is the cost of the main-actor feed-count fetch alone |
| `article-list-derivation` | 11.0 ms @ 10,358 articles | `TodayView.filteredArticles`, one render |

`article-list-derivation` is the number U3 and U4 must flatten. It should stay roughly
constant as the store grows; today it scales with total article count because the query is
unbounded and each article's `feed` relationship is faulted during filtering.

Only one derivation exceeded the 10 ms log threshold per launch, so the per-render figure is
a floor, not a total — `categories`, `unreadCount`, `favoritesCount`, `hasPodcastArticles`,
and `hasAltArticles` each make their own full pass and are not individually instrumented.

## Sync

Forced by backdating `com.today.lastGlobalSyncDate` (see harness below).

| Phase | Measured |
|---|---|
| `sync-total` | **4841 ms** |
| `sync-fetch-parse` | **4385 ms** |
| `sync-insert` | 438 ms |
| `sync-feed-fetch` (per feed) | 268 ms – **1650 ms** |
| Outcome | 9 fetched, 1 not modified (304), 21 failed |

**The head-of-line blocking U8 targets is visible here.** The slowest single feed took
1650 ms, but the whole fetch-parse phase took 4385 ms — 2.7× the slowest feed. With 31 feeds
processed in sequential `chunked(into: 5)` batches, the phase cost is the *sum of each
chunk's slowest feed* rather than the slowest feed overall. True bounded concurrency should
bring `sync-fetch-parse` close to the slowest-feed figure plus queueing.

Caveat that makes this an understatement: 21 of the 31 feeds are seeded
`https://example.invalid/...` URLs that fail fast. Real feeds are slower and more variable,
so the gap between the barrier design and bounded concurrency is wider in production than
2.7×.

`sync-insert` at 438 ms is a single terminal `save()`, which invalidates every unbounded
`@Query` at once — the mid-sync stall U9 spreads out.

## U3 result: article-list derivation

A/B on the **same** 40,000-article store (20 feeds × 2,000, dates spread over 90 days),
pre-U3 build vs post-U3 build installed over the same container so neither the data nor the
schema differs.

| | per render | renders logged during launch | main-thread total |
|---|---|---|---|
| Pre-U3 (`905246e`) | 28.6 – 33.9 ms | 11 | ≈ 330 ms |
| Post-U3 (`605413a`) | 11.4 ms | 1 | < 100 ms |

Only durations above the 10 ms threshold are logged, so the post-U3 figure is an upper
bound: one render logged at 11.4 ms (which includes cold materialisation of the window and
its prefetched feeds) and every later render fell below 10 ms.

The scaling claim (R8) holds against the original baseline too: derivation was 11.0 ms at
10,358 articles before U3 and is 11.4 ms at 40,000 articles after it. Roughly 4× the store
for no change in cost, because the cost now tracks the size of the *window* — one day of
articles — rather than the size of the store. Pre-U3 over the same range went 11.0 ms →
~30 ms, which is the linear growth the plan set out to remove.

The repeat-render count matters as much as the per-render figure: the pre-U3 view derived
six independent full-array passes and did so on every render, 11 times during launch alone.

## U4 result: sidebar (iPad / macOS)

iPad Pro 13-inch simulator, 10,000-article store (20 feeds × 500, dates spread over 90 days):

```
SidebarContentView appeared with 20 feeds, 900 articles in window
```

900 instead of 10,000 — the rolling 7-day window plus a 1-day descriptor margin over a
90-day spread, which is the expected ≈8/90 of the store. `article-list-derivation` no longer
logs for the sidebar at all, so it is under the 10 ms threshold.

The `@State` cache is gone along with its 10 ms `Task.sleep` layout-escape. That cache was
also a correctness bug: keyed on `allArticles.count`, so a sync that replaced articles
without changing the total served stale data indefinitely.

Runtime-verified on iPad (which is the same `SidebarContentView` code path as macOS). The
macOS app compiles but was not launched, to avoid touching a local development store.

## U5 result: no unbounded article query remains

All seven `@Query` declarations over `Article` now build from an explicit descriptor with
both a predicate and a `fetchLimit`:

| View | Bound |
|---|---|
| `TodayView` (via `ArticleWindow`) | date window + selection |
| `SidebarContentView` | rolling 7-day window + margin |
| `FeedDetailView` | feed predicate + limit |
| `FeedArticlesView` | feed predicate + limit |
| `FeedNewsletterView` (×2) | feed + read-state, limit 15 each |
| `AIChatView` | rolling 8-day window |

`AIChatView` needed care: two of its three consumers already applied a 7-day window, but
`generateResponse` passed every non-alt article to `AIService`, which uses only
`prefix(15)` for context yet injects `Total articles: N` / `Unread: N` into the prompt — and
the pattern-based fallback answered "how many articles do you have" from `articles.count`.
Those are library-wide facts, so bounding the fetch alone would have changed the
assistant's answers. They are now counted separately by `ArticleQuery.nonAltCounts` and
passed to `AIService` explicitly, which is both exact and free of a full fetch.

### Regression found and fixed during U5

Bounding `TodayView` in U3 turned the plain-text backfill from a filter over an
already-materialised array into its own predicate fetch — an unindexed table scan on the
main actor **on every appearance of the view**, measured at **512.7 ms** on the
40,000-article store even with nothing to backfill.

Now guarded by a `UserDefaults` completion flag and batched at 500 rows, so it works through
a large store across launches and then stops scanning entirely. Two consecutive launches on
the 40,000-article store show no backfill interval at all, with derivation steady at
10.4–11.3 ms.

## U6 result: derived fields computed once, not per row

`hasMinimalContent` cost up to three `htmlToPlainText` passes — five regular expressions and
a dozen string replacements each — and was read per visible row while scrolling. It is now
computed at insert and stored in `isMinimalContentCached`, with the computation kept as a
fallback for articles that predate the field.

The backfill for those older articles moved out of `TodayView.task` (main actor, re-running
on every appearance) into `DatabaseMigration.backfillDerivedArticleFields`, which runs once
off the main actor from `TodayApp`.

### The backfill was O(n²) on the first attempt

The obvious implementation — batch on "field IS NULL" — re-scans the already-filled rows
every batch, on an unindexed column. Measured on the 40,000-article store at roughly
**240 rows/second**, i.e. minutes of background work, with a `@Query` invalidation after each
batch that showed up as repeated `article-list-derivation` at 10–36 ms while the user reads.

Replaced with keyset pagination over the indexed `publishedDate`, so each batch is an index
seek and the whole backfill is one ordered pass. The test suite went from **19.7s to 3.0s**
purely from this change, since the 1,100-row backfill test was doing the same quadratic work.

Not re-measured on device: the completion flag cannot be reliably cleared from outside the
app, because the live CFPreferences value shadows the on-disk plist — the same gotcha
documented above for `lastGlobalSyncDate`. Correctness and termination are covered by tests
(1,100 rows across batch boundaries, values checked against the computation).

One accepted imprecision: the cursor advances by `publishedDate`, so articles sharing a
batch boundary timestamp can be skipped. Harmless — a skipped article keeps computing on
demand via the accessor's fallback.

## Confirmed: sync was running on the main thread

Measured with `Thread.isMainThread` probes during a forced sync, before any change:

| Phase | On main thread? |
|---|---|
| `syncAllFeeds` | **yes** |
| `parseAllFeedsInBackground` | **yes** |
| `insertArticlesInChunks` | **yes** |
| `context.save()` | **yes** |
| individual feed fetch tasks | no |

Only the `withTaskGroup` fetch closures escaped, because `@Sendable` task-group closures do
not inherit actor isolation. Everything else — including article insertion and the SwiftData
save, measured at **438 ms** in the baseline — was main-thread work.

The 2026-05-31 plan removed `@MainActor` from `BackgroundSyncManager` specifically to prevent
this. That change was silently undone by `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
re-imposes main-actor isolation on every unannotated declaration, including
`enum BackgroundFeedSync`.

### `nonisolated` alone was not the fix

Marking the pipeline `nonisolated` changed nothing — still `main=true`. The project also sets
`SWIFT_APPROACHABLE_CONCURRENCY = YES`, under which a `nonisolated async` function runs on
**the caller's** executor (`nonisolated(nonsending)` semantics). Since the caller was
main-actor, so was the callee.

`@concurrent` is the annotation that forces the global executor. With it, all three phases
report `main=false`.

Both settings are now recorded in `assert(!Thread.isMainThread, …)` guards at the top of
`syncAllFeeds` and `insertArticlesInChunks`, so dropping `@concurrent` trips a debug
assertion instead of quietly restoring a main-thread stall.

### Side effect: the head-of-line problem became visible

With the pipeline off-main, a forced sync where five dead feeds hung showed:

```
sync-feed-fetch  14634 ms  ×5   (the 15s request timeout)
sync-feed-fetch    392–630 ms  ×3
sync-fetch-parse 16299 ms
```

Five feeds timing out inside one `chunked(into: 5)` wave stall the entire phase. This is
exactly what U8 removes, and it also confirms the U5 timeout works — 14.6 s against the
configured 15 s cap, rather than `URLSession`'s 60 s default.

## Note: this module is main-actor by default

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set, so **every unannotated declaration is
main-actor isolated**. This is easy to miss and has two consequences:

- Pure helpers usable from background work need explicit `nonisolated`. `String.strippingHTML`
  and `htmlToPlainText` are now marked so, as is `Article.computeIsMinimalContent`.
- More importantly, `BackgroundFeedSync.syncAllFeeds` and `insertArticlesInChunks` carry no
  isolation annotations, so they are likely running **on the main actor** despite the earlier
  plan having removed `@MainActor` from `BackgroundSyncManager`. The `withTaskGroup` fetch
  closures do escape (U1 traces show `sync-feed-fetch` across several threads), but the
  insert phase would not. `sync-insert` measured 438 ms at baseline; if that is main-actor
  work it is a 438 ms main-thread block and probably the largest remaining sync win.
  **Unverified — check before U9.**

## Known gap: indexes do not reach existing stores

`#Index` declarations (U2) are applied when a store is **created**, not when one is
migrated. Confirmed by inspecting `sqlite_master` on both:

| Store | Indexes on `ZARTICLE` / `ZFEED` |
|---|---|
| Fresh install | `ZARTICLE_ZFEED_INDEX`, `Z_Article_SwiftDataIndexOnBinarypublishedDate`, `…guid`, `…isReadpublishedDate`, `…isFavoritepublishedDate`, `Z_Feed_SwiftDataIndexOnBinaryisActive` |
| Migrated from pre-U2 schema | `ZARTICLE_ZFEED_INDEX` only |

The migrated store opens cleanly with no data loss (10,358 articles / 31 feeds before and
after), so this is not a correctness problem — upgrading users simply run the new bounded
predicates against an unindexed table.

That is still much cheaper than what they do today: the current code materialises every
`Article` and faults each one's `feed` relationship in Swift, whereas a bounded predicate
without an index is a SQLite table scan that materialises only the window. Indexes make it
better, not viable.

Closing the gap requires a `VersionedSchema` plus `SchemaMigrationPlan`. That is a real
migration on a shipping app, so it is a deliberate decision rather than a side effect of
this performance work.

## Harness

Seed a store (idempotent — safe to leave the flag on for later runs):

```
xcrun simctl launch <device> jakespurlock.Today \
  -SeedLargeStore -SeedFeedCount 20 -SeedArticlesPerFeed 500
```

Capture signposts. `Perf` logs at `info` level, so `--level debug` is required — the default
`log stream` level silently drops them:

```
xcrun simctl spawn <device> log stream --style compact --level debug \
  --predicate 'subsystem BEGINSWITH "com.today"'
```

Force a sync. `needsSync()` gates on a 2-hour window, so backdate the key. Note it must be
written through `defaults`, not PlistBuddy: the live value is cached in CFPreferences and may
not be flushed to `Library/Preferences/jakespurlock.Today.plist`, so the on-disk plist can
look empty while the app still reads a recent date.

```
xcrun simctl spawn <device> defaults write jakespurlock.Today \
  com.today.lastGlobalSyncDate -date "2020-01-01 00:00:00 +0000"
```

Inspect the store directly:

```
sqlite3 "$(xcrun simctl get_app_container <device> jakespurlock.Today data)/Library/Application Support/default.store" \
  "SELECT COUNT(*) FROM ZARTICLE; SELECT COUNT(*) FROM ZFEED;"
```

For Instruments rather than Console, the signpost intervals appear under the
`com.today` / `performance` subsystem on the timeline alongside the main-thread trace.
