---
applyTo: "Today/Services/**/*.swift"
---

# Services Layer Instructions

## Architecture Patterns

Services handle business logic, network operations, and data processing. Follow these patterns:

### Thread Safety
- **FeedManager** and **BackgroundSyncManager**: Use `@MainActor` for UI updates
- **RSSParser** and parsers: Can run on background threads
- **AIService**: Most operations can be background, but results should dispatch to MainActor for UI updates

### Async/Await
- All network operations MUST use async/await (no completion handlers)
- Use `Task` for concurrent operations
- Handle errors with try/catch, not Result types

### Service Organization

**Parsers** (`RSSParser`, `JSONFeedParser`, `RedditJSONParser`, `AtomFeedTests`):
- Stateless parsing logic
- XMLParser/JSONDecoder based
- Return parsed data structures, don't interact with database
- Support multiple date formats and edge cases

**Managers** (`FeedManager`, `BackgroundSyncManager`, `CategoryManager`):
- Own ModelContext for database operations
- Handle state management
- Coordinate between parsers and data layer
- `@MainActor` for UI-related managers

**Players** (`ArticleAudioPlayer`, `PodcastAudioPlayer`):
- Manage AVAudioPlayer/AVPlayer state
- Handle Now Playing info updates
- Background audio session management

**AI Services** (`AIService`, `OnDeviceAIService`):
- NaturalLanguage framework for iOS 18+
- Apple Intelligence for iOS 26+ (with fallback)
- Process text on background threads, return results

### Common Patterns

**Creating a new service:**
```swift
class MyService {
    static let shared = MyService() // Singleton if stateless
    
    private init() { }
    
    func performOperation() async throws -> Result {
        // Implementation
    }
}
```

**Service with MainActor:**
```swift
@MainActor
class UIService: ObservableObject {
    @Published var state: State
    
    func updateUI() async {
        // Safe to update UI directly
    }
}
```

### Testing Services
- Mock network responses using test data
- Test error handling for malformed feeds
- Test date parsing with various formats
- Use XCTest async test methods: `func testAsync() async throws`

### Common Issues
- **Network timeouts**: Default URLSession timeout may be too short for large feeds
- **XML parsing edge cases**: Handle missing elements, malformed XML, non-standard date formats
- **Background task limits**: iOS limits background execution time to ~30 seconds
- **Memory in parsers**: Large feeds can cause memory spikes; consider streaming parsers for very large feeds
