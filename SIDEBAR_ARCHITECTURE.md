# Sidebar Architecture Diagram

## Component Hierarchy

```
TodayApp
└── ContentView (size class detection)
    ├── CompactContentView (iPhone - horizontalSizeClass == .compact)
    │   └── TabView
    │       ├── TodayView (tab 1)
    │       ├── FeedListView (tab 2)
    │       ├── AIChatView (tab 3)
    │       └── SettingsView (tab 4)
    │
    └── SidebarContentView (iPad - horizontalSizeClass == .regular)
        └── NavigationSplitView
            ├── Sidebar (List)
            │   ├── Section: Main
            │   │   ├── Today (SidebarItem.today)
            │   │   └── Manage Feeds (SidebarItem.feeds)
            │   ├── Section: [Category Name]
            │   │   └── [Feed Items] (SidebarItem.feed(id))
            │   └── Section: AI & Settings
            │       ├── AI Summary (SidebarItem.aiChat)
            │       └── Settings (SidebarItem.settings)
            │
            └── Detail Pane (switch on selectedSidebarItem)
                ├── TodayView (case .today)
                ├── FeedListView (case .feeds)
                ├── FeedDetailView (case .feed(id))
                │   └── List of articles with search
                ├── AIChatView (case .aiChat)
                └── SettingsView (case .settings)
```

## Data Flow

```
Feed Model (SwiftData)
    ↓
@Query in SidebarContentView
    ↓
Filter by Alt category visibility
    ↓
Group by category (lowercase normalized)
    ↓
Sort categories & feeds alphabetically
    ↓
Render in sidebar sections
    ↓
User selects feed
    ↓
FeedDetailView with predicate filter
    ↓
Display articles from selected feed
```

## Navigation State

```swift
enum SidebarItem: Hashable {
    case today                          // Show all articles
    case feeds                          // Manage feed subscriptions
    case feed(PersistentIdentifier)     // Show specific feed's articles
    case aiChat                         // AI chat interface
    case settings                       // App settings
}
```

## Performance Optimization

### Before (Inefficient)
```
Database → Fetch ALL articles → Filter in Swift → Display
```

### After (Optimized)
```
Database → Filter with predicate → Fetch matched articles → Display
```

### SwiftData Predicate
```swift
let predicate = #Predicate<Article> { article in
    article.feed?.id == feedId
}
_articles = Query(
    filter: predicate,
    sort: \Article.publishedDate,
    order: .reverse
)
```

## Size Class Detection

```
Device           | horizontalSizeClass | Layout Used
-----------------|---------------------|------------------
iPhone Portrait  | .compact            | CompactContentView (TabView)
iPhone Landscape | .compact            | CompactContentView (TabView)
iPad Portrait    | .regular            | SidebarContentView (Split View)
iPad Landscape   | .regular            | SidebarContentView (Split View)
iPad Split View  | .compact/.regular   | Adaptive based on size
Mac              | .regular            | SidebarContentView (Split View)
```

## Feature Matrix

| Feature                    | iPhone | iPad |
|---------------------------|--------|------|
| Tab Bar Navigation        | ✅     | ❌   |
| Sidebar Navigation        | ❌     | ✅   |
| Feed Categories           | Via Feeds Tab | Sidebar Sections |
| Direct Feed Access        | Multiple Taps | Single Click |
| Mini Audio Player         | ✅     | ✅   |
| Search in Feeds           | ✅     | ✅   |
| Article Navigation        | ✅     | ✅   |
| OPML Import/Export        | ✅     | ✅   |

## Code Organization

```
Today/ContentView.swift
├── ContentView (37 lines)
│   └── Size class detection and routing
├── CompactContentView (52 lines)
│   └── iPhone TabView layout
├── SidebarContentView (125 lines)
│   └── iPad NavigationSplitView layout
└── FeedDetailView (73 lines)
    └── Feed-specific article list
```

## Integration Points

### Existing Views Used
- `TodayView`: Main article list (unchanged)
- `FeedListView`: Feed management (unchanged)
- `AIChatView`: AI chat interface (unchanged)
- `SettingsView`: App settings (unchanged)
- `ArticleDetailSimple`: Article detail (unchanged)

### New Components
- `CompactContentView`: iPhone layout wrapper
- `SidebarContentView`: iPad sidebar layout
- `FeedDetailView`: Feed-specific article view
- `SidebarItem` enum: Navigation state

### Shared State
- `@AppStorage("appearanceMode")`: Theme setting
- `@AppStorage("accentColor")`: Accent color
- `@AppStorage("showAltCategory")`: Alt category visibility
- `ArticleAudioPlayer.shared`: TTS audio player
- `PodcastAudioPlayer.shared`: Podcast player

## Error Handling

```
User Action          | Scenario              | Handling
---------------------|----------------------|------------------------
Select deleted feed  | Feed no longer exists | ContentUnavailableView
Empty feed          | No articles in feed   | Empty List (SwiftUI)
Search no results   | No matching articles  | Empty List (SwiftUI)
Network error       | Sync fails            | Handled by existing code
```

## Future Extensibility

Easy to add:
- ✅ New sidebar sections
- ✅ Feed icons/favicons
- ✅ Unread badges
- ✅ Context menus
- ✅ Drag-and-drop
- ✅ Keyboard shortcuts
- ✅ Custom categories

## Testing Strategy

1. **Unit Tests**: Not applicable (UI-only changes)
2. **Integration Tests**: Manual testing required
3. **Device Testing**:
   - iPhone SE (compact)
   - iPhone 15 Pro (compact)
   - iPad Air (regular)
   - iPad Pro (regular)
4. **Orientation Testing**:
   - Portrait mode
   - Landscape mode
   - Split view (iPad)
5. **State Testing**:
   - Empty feeds list
   - Single category
   - Multiple categories
   - Alt category on/off
   - Feed deletion while viewing
