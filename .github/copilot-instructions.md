# GitHub Copilot Instructions

This file provides guidance to GitHub Copilot when working with code in this repository.

## Project Overview

"Today" is a SwiftUI iOS application that serves as an RSS reader with AI-powered content summarization. It uses SwiftData for persistent storage, Apple's NaturalLanguage framework and Apple Intelligence for text analysis, and supports background fetch for automatic feed syncing.

**Key Technologies:**
- SwiftUI for declarative UI
- SwiftData for persistence (successor to Core Data)
- Swift Concurrency (async/await)
- Apple Intelligence (iOS 26+) with NaturalLanguage framework fallback
- Background Tasks (BGTaskScheduler)
- Safari View Controller for in-app browsing

## Build and Development Commands

### Building the Project

```bash
# Build for debug
xcodebuild -project Today.xcodeproj -scheme Today -configuration Debug build

# Build for release
xcodebuild -project Today.xcodeproj -scheme Today -configuration Release build

# Clean build artifacts
xcodebuild -project Today.xcodeproj -scheme Today clean

# Open in Xcode
open Today.xcodeproj
```

### Running Tests

```bash
# Run all tests
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test suite
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TodayTests/TexturizerTests
```

### Version Management

```bash
# Update marketing version
xcrun agvtool new-marketing-version 1.3

# Increment build number
xcrun agvtool next-version -all
```

## Project Structure

```
Today/
├── Models/           # SwiftData models (Feed, Article)
├── Views/            # SwiftUI views
├── Services/         # Business logic (RSS parsing, AI, background sync)
├── Utilities/        # Helper utilities (Texturizer)
└── Resources/        # Assets and configuration
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
- **OnDeviceAIService.swift**: Uses Apple Intelligence (iOS 26+) for advanced AI summaries with graceful fallback to NaturalLanguage framework.
- **BackgroundSyncManager.swift**: Manages `BGAppRefreshTask` for background feed syncing. Registers background tasks on app launch and schedules periodic syncs (minimum 15 min intervals).

### View Layer

Views are located in `Today/Views/`:

- **TodayView.swift**: Main article list with day-based navigation (Today/Yesterday/Older), category filtering, and search. Uses `@Query` with sort descriptors for reactive data updates.
- **FeedListView.swift**: Feed management interface with add/remove/sync capabilities. Uses `@StateObject` for FeedManager lifecycle.
- **AIChatView.swift**: Chat-style interface for AI interactions. Maintains conversation history with `ChatMessage` structs.
- **ArticleDetailSimple.swift**: Article detail view with toolbar actions (share, favorite, mark read).
- **SettingsView.swift**: User preferences including theme, accent color, font selection, and AI provider.

### App Structure

- **TodayApp.swift**: Entry point that initializes BackgroundSyncManager and ModelContainer. Schedules background fetch on app launch.
- **ContentView.swift**: TabView-based navigation between Today, Feeds, and AI Summary tabs.

## Key Development Patterns

### SwiftData Usage

- **Access model context**: Use `@Environment(\.modelContext)` in views
- **Query data**: Use `@Query` with predicates and sort descriptors
  ```swift
  @Query(sort: \Article.publishedDate, order: .reverse) var articles: [Article]
  ```
- **Insert**: `modelContext.insert(newObject)`
- **Delete**: `modelContext.delete(object)` - cascade rules handle related objects
- **No explicit save needed** for @Query views - SwiftData autosaves
- **For background work**: Create separate ModelContext from shared ModelContainer

### Swift Concurrency

- All network operations use async/await
- FeedManager and BackgroundSyncManager use `@MainActor` for thread-safe UI updates
- Use `Task` for concurrent operations

### Background Tasks

- Uses BGTaskScheduler with task identifier `com.today.feedsync`
- Requires "Background Modes" capability with "Background fetch" enabled
- Must add task identifier to "Permitted background task scheduler identifiers" in Info.plist
- iOS controls when background tasks actually run (for battery optimization)
- Test with Debug > Simulate Background Fetch in Xcode

## Coding Guidelines

### Adding New SwiftData Models

When adding new SwiftData models:
1. Create the model class with `@Model` macro
2. Add it to the schema array in `TodayApp.swift:14-17`
3. The ModelContainer will handle migrations automatically for simple schema changes

### Working with RSS Feeds

- RSS parsing is handled by `RSSParser` using XMLParser delegate pattern
- Duplicate articles are prevented using GUID matching in `FeedManager`
- Feed sync is idempotent - safe to call multiple times
- Support both RSS 2.0 and Atom formats

### AI Integration

- **Apple Intelligence**: Primary AI provider on iOS 26+ (OnDeviceAIService.swift)
- **NaturalLanguage**: Fallback provider for older iOS versions (AIService.swift)
- Uses NLTagger for keyword extraction
- Analyzes trends by grouping articles by feed and category
- Pattern matching for conversational queries in `generateResponse()`
- To integrate more advanced AI: Consider Core ML models or MLX Swift

### Typography and Text Processing

- **Texturizer.swift** (GPL v2+): WordPress-style smart quotes and em/en dashes
- Isolated from main application to maintain license clarity
- Converts straight quotes to curly quotes, hyphens to em/en dashes

## Testing

### Common Test Scenarios

- **Test RSS parsing**: Use `RSSParser` with sample XML in tests
- **Test feed sync**: Mock FeedManager methods
- **Test AI summaries**: Use sample article text
- **Test SwiftData**: Use in-memory ModelContainer for tests

## License Information

This project uses a dual-license structure:

- **Main Application**: MIT License
- **Texturizer Component** (`Today/Utilities/Texturizer.swift`): GPL v2+ (derived from WordPress)

When modifying or adding code:
- Keep Texturizer isolated to maintain license clarity
- Add GPL header comments to any WordPress-derived code
- Use MIT license for all other new code

## Development Tips

### Common Tasks

- **Manually trigger sync**: Call `FeedManager.syncAllFeeds()` from any view
- **Simulate background fetch**: Debug menu > Simulate Background Fetch (app must be running)
- **Reset all data**: Delete app and reinstall, or clear in Settings > General > iPhone Storage

### Debugging

- Use Xcode's debug console for print statements
- Use breakpoints in Xcode for stepping through code
- Use Instruments for performance profiling
- Check Console.app for background task logs

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Use Swift's type inference where appropriate
- Prefer `let` over `var` when possible
- Use guard statements for early exits

## Privacy and Security

- All data stored locally with SwiftData
- No analytics or tracking
- No account creation required
- AI processing happens on-device
- Only network requests are for fetching RSS feeds

## Key Dependencies

- **SwiftUI**: UI framework (iOS 18.0+)
- **SwiftData**: Persistence and data modeling
- **NaturalLanguage**: Text analysis and keyword extraction
- **Apple Intelligence**: Advanced AI summaries (iOS 26+)
- **BackgroundTasks**: Background sync support
- **SafariServices**: In-app web browsing

## Additional Resources

- [README.md](../README.md) - User-facing documentation
- [CLAUDE.md](../CLAUDE.md) - Detailed architecture guide
- [RELEASE_PROCESS.md](../RELEASE_PROCESS.md) - Release and deployment guide
- [PROJECT_SUMMARY.md](../PROJECT_SUMMARY.md) - Feature documentation
