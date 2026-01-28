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

# Run tests
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15'
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
- **MainActor**: FeedManager and BackgroundSyncManager use `@MainActor` for thread-safe UI updates
- **Relationships**: Feed-Article is one-to-many with cascade delete
- **Background Tasks**: Uses BGTaskScheduler with task identifier `com.today.feedsync`

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

### Common Tasks
- **Test RSS parsing**: Use `RSSFeedService.shared.fetchFeed(url:)` in a test
- **Manually trigger sync**: Call `FeedManager.syncAllFeeds()` from any view
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
