# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Today" is a SwiftUI iOS application that serves as an RSS reader with AI-powered content summarization. It uses SwiftData for persistent storage, Apple's NaturalLanguage framework for text analysis, and supports background fetch for automatic feed syncing.

## Build and Development Commands

### Building and Running
```bash
# Build the project
xcodebuild -project Today.xcodeproj -scheme Today -configuration Debug build

# Build for release
xcodebuild -project Today.xcodeproj -scheme Today -configuration Release build

# Clean build artifacts
xcodebuild -project Today.xcodeproj -scheme Today clean

# Run tests (pick a simulator that exists: xcrun simctl list devices available)
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 17'

# macOS target — build this too, it shares most of the source
xcodebuild build -project Today.xcodeproj -scheme "Today MacOS" -destination 'platform=macOS'
```

### Opening in Xcode
```bash
open Today.xcodeproj
```

## Architecture

### Data Layer - SwiftData
Models are located in `Today/Models/`:
- **Feed.swift**: RSS feed subscriptions with title, URL, category, and relationship to articles. Uses `@Relationship(deleteRule: .cascade)` to auto-delete articles when feed is deleted.
- **Article.swift**: Individual RSS articles with metadata (title, link, description, published date, author, guid). Includes `isRead`, `isFavorite`, and `aiSummary` properties.
- **ModelContainer**: Initialized in `TodayApp.swift` with schema containing `Feed` and `Article`. Configured for persistent storage.

### Service Layer
Services are located in `Today/Services/`:
- **RSSParser.swift**: XMLParser-based RSS feed parser. Handles RSS and Atom formats with multiple date format support. Returns parsed article data without direct database access.
- **FeedManager.swift**: `@MainActor` class managing feed subscriptions and syncing. Handles duplicate detection using article GUIDs. Owns ModelContext for database operations.
- **AIService.swift**: Uses Apple's NaturalLanguage framework for content analysis. Provides article summarization, keyword extraction, trend analysis, and conversational responses.
- **BackgroundSyncManager.swift**: Manages `BGAppRefreshTask` for background feed syncing. Registers background tasks on app launch and schedules periodic syncs (minimum 15 min intervals).

### View Layer
Views are located in `Today/Views/`:
- **TodayView.swift**: Main article list with category filtering, search, and 7-day time window. Uses `@Query` with sort descriptors for reactive data updates.
- **FeedListView.swift**: Feed management interface with add/remove/sync capabilities. Uses `@StateObject` for FeedManager lifecycle.
- **AIChatView.swift**: Chat-style interface for AI interactions. Maintains conversation history with `ChatMessage` structs.

### App Structure
- **TodayApp.swift**: Entry point that initializes BackgroundSyncManager and ModelContainer. Schedules background fetch on app launch.
- **ContentView.swift**: TabView-based navigation between Today, Feeds, and AI Summary tabs.

### Key Patterns
- **SwiftData Queries**: Views use `@Query` with predicates and sort descriptors for reactive data fetching
- **Async/Await**: All network operations use Swift concurrency
- **Concurrency**: see the Concurrency section below — the build settings here make this counter-intuitive
- **Relationships**: Feed-Article is one-to-many with cascade delete
- **Background Tasks**: Uses BGTaskScheduler with task identifier `com.today.feedsync`

## Concurrency — read this before touching background work

Two build settings make isolation behave in ways that have already caused one silent
regression:

```
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_APPROACHABLE_CONCURRENCY = YES
```

**Every unannotated declaration is main-actor isolated.** A plain `func`, a `static func` on
an enum, a `String` extension — all main actor unless marked otherwise. Removing `@MainActor`
from a class does *not* move its methods off the main thread; the setting puts it straight
back. This silently undid an earlier fix, and article insertion plus SwiftData saves ran on
the main thread for months afterwards.

**`nonisolated` is not enough for async work.** Under approachable concurrency a
`nonisolated async` function runs on the *caller's* executor. If the caller is main-actor, so
is the callee. Use **`@concurrent`** to force the global executor:

```swift
@concurrent nonisolated static func syncAllFeeds(container: ModelContainer) async { ... }
```

Pure helpers called from background code need plain `nonisolated` (see
`String.strippingHTML`, `Article.computeIsMinimalContent`).

**Verify, don't assume.** `BackgroundFeedSync.syncAllFeeds` and `insertArticlesInChunks` open
with `assert(!Thread.isMainThread)` in DEBUG for exactly this reason. If you add background
work, add the same guard — annotations that look right and do nothing are the failure mode
here.

---

## SwiftData constraints worth knowing

**`#Predicate` is more limited than it looks.** Pinned in
`TodayTests/PredicateCapabilityProbeTests.swift`:

- `lowercased()` is a **compile error** inside `#Predicate`
- `contains()` over a captured array combined with `flatMap`/`??` compiles but fails at fetch
  time with "unimplemented SQL generation ... (bad LHS)", and raises an ObjC exception that
  `XCTAssertThrowsError` cannot catch
- **SQL NULL semantics differ from Swift optionals.** `feed?.category != "Alt"` drops rows
  where `feed` is nil, because `NULL != 'Alt'` is NULL, not true. Swift's optional chaining
  returns true. Admit nil explicitly:
  `feed == nil || (feed?.category != "Alt" && ...)`

**Every `Article` query must be bounded** — predicate *and* `fetchLimit`. Build descriptors
with `ArticleQuery` rather than by hand, so filter semantics stay identical across the iOS
list, the sidebar and the feed views. Add `relationshipKeyPathsForPrefetching: [\.feed]`
whenever the results touch `article.feed`.

**`#Index` only applies to newly created stores.** SwiftData's lightweight migration does not
add indexes to an existing store, so upgrading users run unindexed until a `VersionedSchema`
migration exists. Verify schema changes against a *pre-existing* store, not just a fresh one.

**Prefer fetch-by-identifier to `context.model(for:)`** when the object may have been deleted
— the latter can return an unrealised stub that an `as?` cast silently skips.

---

## Feed URLs

`addFeed` stores a canonical form: `http://` upgraded to `https://` (except the domains in
`FeedURLNormalizer.httpOnlyDomains`), and Reddit URLs rewritten to `.json`.

**Anything comparing a feed URL against a stored feed must canonicalise both sides through
`FeedURLNormalizer`.** This logic previously lived only inside `addFeed`, so OPML sync
compared URLs as listed and never matched — feeds were deactivated on every sync and stopped
updating with no visible symptom.

---

## Measuring performance

`Perf` / `PerfPhase` wrap `OSSignposter` for launch, sync and list-derivation phases. Left in
release builds on purpose — intervals cost nothing when nothing is recording. Prefer them to
`print`.

DEBUG launch arguments (see `TodayApp.init`):

| Flag | Effect |
|---|---|
| `-SeedLargeStore` | Generate a large store; `-SeedFeedCount`, `-SeedArticlesPerFeed` |
| `-ForceSyncOnLaunch` | Clear the sync date so this launch syncs |
| `-ResetArticlesOnLaunch` | Delete all articles and reset sync state |

```bash
xcrun simctl spawn <device> log stream --style compact --level debug \
  --predicate 'subsystem BEGINSWITH "com.today"'
```

`--level debug` is required — `Perf` logs at info level, which the default stream drops.

**UserDefaults cannot be changed from outside the app.** The live CFPreferences value shadows
the on-disk plist, so `defaults write` from the host is silently ignored. That is why
`-ForceSyncOnLaunch` exists rather than backdating the key externally.

Baselines and method: `docs/performance-baseline.md`.

---

## Key Dependencies
- SwiftUI: UI framework
- SwiftData: Persistence and data modeling (successor to Core Data)

## Development Notes

### Adding New Models
When adding new SwiftData models:
1. Create the model class with `@Model` macro
2. Add it to the schema array in `TodayApp.swift:14-17`
3. The ModelContainer will handle migrations automatically for simple schema changes

### Working with RSS Feeds
- RSS parsing is handled by `RSSParser` using XMLParser delegate pattern
- Duplicate articles are prevented using GUID matching in `FeedManager`
- Feed sync is idempotent - safe to call multiple times

### AI Summarization
- Uses Apple's NaturalLanguage framework (NLTagger) for keyword extraction
- Analyzes trends by grouping articles by feed and category
- Pattern matching for conversational queries in `generateResponse()`
- To integrate more advanced AI: Consider Core ML models or MLX Swift

### Background Fetch
- Requires "Background Modes" capability with "Background fetch" enabled
- Must add `com.today.feedsync` to "Permitted background task scheduler identifiers" in Info.plist
- iOS controls when background tasks actually run (for battery optimization)
- Test with Debug > Simulate Background Fetch in Xcode

### Working with SwiftData
- Access model context via `@Environment(\.modelContext)`
- Query data using `@Query` with predicates: `@Query(sort: \Article.publishedDate, order: .reverse)`
- Insert: `modelContext.insert(newObject)`
- Delete: `modelContext.delete(object)` - cascade rules handle related objects
- No explicit save needed for @Query views - SwiftData autosaves
- For background work: Create separate ModelContext from shared ModelContainer

### Tests

`TodayTests` is a **synchronized folder group**, so a new `.swift` file in `TodayTests/` joins
the target automatically — no project edit. It was not always so: two test files sat on disk
for months without ever being target members, and one of them had never passed.

`MockURLProtocol` (in `ConditionalHTTPClientTests.swift`) is shared by several suites and
supports per-URL delays. Two traps recorded there: `Thread.sleep` inside
`URLProtocol.startLoading` serialises every request, and an unsynchronised read of its
in-flight counter reports 0 while requests plainly overlap.

`ConditionalHTTPClient.conditionalFetch`, `BackgroundFeedSync.syncAllFeeds` and
`parseAllFeedsInBackground` all take an injectable `URLSession`, so the whole sync pipeline is
testable without network.

### Common Tasks
- **Test RSS parsing**: Use `RSSFeedService.shared.fetchFeed(url:)` in a test
- **Manually trigger sync**: `BackgroundSyncManager.shared.triggerManualSync()` (the `FeedManager.syncAllFeeds()` path still exists but is legacy)
- **Simulate background fetch**: Debug menu > Simulate Background Fetch (app must be running)
- **Reset all data**: Delete app and reinstall, or clear in Settings > General > iPhone Storage

## Emergency Commands

### Fix Oversized Image Bug
When I say "fix image bug" or "fix session images", run this repair:

1. **Session selection** (first matching option):
   - Explicit path provided → use that file
   - Session ID provided → find matching .jsonl in ~/.claude/projects/*/
   - "list sessions" → show all sessions (ID, size, date, first prompt) and wait for selection
   - Custom directory provided → search there instead
   - Default → auto-detect by scanning recent .jsonl files for lines >5,242,880 bytes

2. Backup: copy to `.backup` extension

3. Identify oversized image lines (>5,242,880 bytes per line) using:
   - `grep -n '"type":"image"' <file>` for line numbers
   - Check line sizes with `sed -n '<N>p' <file> | wc -c`

4. Replace oversized lines with: `{"type":"summary","summary":"[Image removed - exceeded 5MB limit]","uuid":"REMOVED-<line-number>"}`

5. Report: file path, images removed, size reduction

6. Provide resume instructions:
   - Terminal: `claude --resume <session-id>`
   - VSCode: Reload window, then use session picker

Be idempotent. Skip lines with "REMOVED-" in uuid. Report if no oversized images found.
