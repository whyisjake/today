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

**Important**: Tests require an iOS Simulator. The project must be run on macOS with Xcode installed.

```bash
# Run all tests
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test suite
xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TodayTests/TexturizerTests

# List available simulators
xcrun simctl list devices available
```

**Available Test Suites:**
- `TodayTests/RSSParserTests` - RSS feed parsing tests
- `TodayTests/AtomFeedTests` - Atom feed format tests
- `TodayTests/JSONFeedTests` - JSON feed format tests
- `TodayTests/RedditRSSTests` - Reddit JSON API tests
- `TodayTests/TexturizerTests` - Typography/text processing tests
- `TodayTests/CategoryManagerTests` - Category management tests
- `TodayTests/ConditionalHTTPClientTests` - HTTP client tests
- `TodayTests/HTMLHelperTests` - HTML parsing helper tests

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

### Test Structure

Tests are located in `TodayTests/` directory:
- Tests use XCTest framework
- Parser tests include sample RSS/Atom/JSON feed data
- Tests run in iOS Simulator environment
- Use `XCTAssert*` macros for assertions

### Common Test Scenarios

- **Test RSS parsing**: Use `RSSParser` with sample XML in tests
- **Test feed sync**: Mock FeedManager methods
- **Test AI summaries**: Use sample article text
- **Test SwiftData**: Use in-memory ModelContainer for tests

### Running Tests in Xcode

1. Open project: `open Today.xcodeproj`
2. Select a simulator device (iPhone 15 or later)
3. Press `Cmd+U` to run all tests
4. Use Test Navigator (Cmd+6) to run individual tests

## License Information

This project uses a dual-license structure:

- **Main Application**: MIT License
- **Texturizer Component** (`Today/Utilities/Texturizer.swift`): GPL v2+ (derived from WordPress)

When modifying or adding code:
- Keep Texturizer isolated to maintain license clarity
- Add GPL header comments to any WordPress-derived code
- Use MIT license for all other new code

## Development Tips

### Environment Requirements

- **macOS Required**: This is an iOS project that requires Xcode on macOS
- **Xcode 16.0+**: Required for iOS 18.0+ development
- **iOS Simulator**: Tests and development require iOS Simulator
- **No CI/CD**: This project uses manual Xcode builds and App Store Connect for releases

### Common Tasks

- **Manually trigger sync**: Call `FeedManager.syncAllFeeds()` from any view
- **Simulate background fetch**: Debug menu > Simulate Background Fetch (app must be running)
- **Reset all data**: Delete app and reinstall, or clear in Settings > General > iPhone Storage

### Debugging

- Use Xcode's debug console for print statements
- Use breakpoints in Xcode for stepping through code
- Use Instruments for performance profiling
- Check Console.app for background task logs

### Common Issues and Workarounds

- **Build fails after version bump**: If `agvtool` doesn't update `MARKETING_VERSION` in project.pbxproj, manually update it with sed or text editor
- **Simulator not found**: Use `xcrun simctl list devices available` to see available simulators
- **Tests timeout**: Some tests may need longer timeout for network operations
- **Background fetch not triggering**: iOS controls when background tasks run; use Debug > Simulate Background Fetch for testing
- **SwiftData migration issues**: For complex schema changes, may need to delete app and reinstall during development

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

## Validation Steps

Before committing changes, validate:

1. **Build succeeds**: Clean build with no warnings
   ```bash
   xcodebuild -project Today.xcodeproj -scheme Today -configuration Debug clean build
   ```

2. **Tests pass**: All test suites complete successfully
   ```bash
   xcodebuild test -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

3. **Manual testing**: Run app in simulator and verify:
   - Can add RSS feeds
   - Articles display correctly
   - Navigation works between tabs
   - Background sync can be triggered manually

4. **Version numbers**: If releasing, verify version/build numbers are updated correctly

## Additional Resources

- [README.md](../README.md) - User-facing documentation
- [CLAUDE.md](../CLAUDE.md) - Detailed architecture guide for Claude AI
- [RELEASE_PROCESS.md](../RELEASE_PROCESS.md) - Detailed release and App Store submission guide
- [PROJECT_SUMMARY.md](../PROJECT_SUMMARY.md) - Feature documentation
- [SETUP.md](../SETUP.md) - Initial setup instructions for new developers
- [BACKGROUND_SETUP.md](../BACKGROUND_SETUP.md) - Background fetch configuration
