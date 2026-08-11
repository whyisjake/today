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
