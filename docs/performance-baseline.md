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
