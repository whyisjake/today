# iPad Sidebar Feature

## Overview

The Today app now features an adaptive layout that automatically switches between a tab-based interface on iPhone and a sidebar-based interface on iPad and Mac. This provides a more native and efficient experience on larger screens while maintaining the familiar tab bar interface on iPhone.

## User Experience

### iPhone (Compact Size Class)
- **Tab Bar Navigation**: Four tabs at the bottom (Today, Feeds, AI Summary, Settings)
- **Familiar iOS pattern**: Traditional iPhone app navigation
- **Optimized for one-handed use**: Easy thumb access to navigation

### iPad (Regular Size Class)
- **Sidebar Navigation**: Collapsible sidebar on the left with all feeds
- **Feed Organization**: Feeds grouped by category (News, Tech, Social, etc.)
- **Direct Feed Access**: Click any feed to see its articles
- **Detail Pane**: Main content area showing selected view
- **Efficient Use of Space**: Makes use of the larger iPad screen

## Technical Implementation

### Architecture

The implementation uses SwiftUI's size class detection to provide adaptive layouts:

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

var body: some View {
    Group {
        if horizontalSizeClass == .regular {
            // iPad/Mac layout with sidebar
            SidebarContentView(modelContext: modelContext)
        } else {
            // iPhone layout with tab bar
            CompactContentView(modelContext: modelContext)
        }
    }
}
```

### Key Components

#### 1. ContentView
- **Purpose**: Top-level view that detects size class and routes to appropriate layout
- **Adaptive**: Automatically switches layouts based on device/window size
- **Shared State**: Manages appearance settings and audio player state

#### 2. CompactContentView (iPhone)
- **Layout**: Traditional TabView with four tabs
- **Navigation**: Bottom tab bar for Today, Feeds, AI Summary, Settings
- **Mini Player**: Floating audio player above tab bar
- **Behavior**: Identical to previous app experience

#### 3. SidebarContentView (iPad/Mac)
- **Layout**: NavigationSplitView with sidebar and detail panes
- **Sidebar Sections**:
  - **Main**: Today and Manage Feeds
  - **Feeds by Category**: Dynamic sections based on feed categories
  - **AI & Settings**: AI Summary and Settings options
- **Detail Pane**: Shows selected content (articles, feed management, AI chat, settings)
- **Mini Player**: Floating audio player above content

#### 4. FeedDetailView
- **Purpose**: Display articles for a specific feed
- **Features**:
  - List of articles from the feed
  - Search functionality
  - Navigation to article detail
  - Shows article title, description, and relative date

### Data Flow

1. **Feed Query**: Uses SwiftData `@Query` to fetch all feeds sorted by title
2. **Category Grouping**: Feeds are grouped by category for sidebar organization
3. **Alt Category Filtering**: Respects user's Alt category visibility setting
4. **Selection State**: Uses `SidebarItem` enum to track selected sidebar item
5. **Navigation**: Uses `PersistentIdentifier` for stable feed references

### SidebarItem Enum

```swift
enum SidebarItem: Hashable {
    case today           // Today's articles view
    case feeds           // Feed management view
    case feed(PersistentIdentifier)  // Specific feed's articles
    case aiChat          // AI chat interface
    case settings        // App settings
}
```

### Feed Organization

Feeds are automatically organized by category in the sidebar:
- Each category becomes a section header
- Feeds within each category are sorted alphabetically
- Alt category respects global visibility setting

## User Features

### iPad Sidebar Features

1. **Feed Categories**
   - Automatically groups feeds by category
   - Alphabetically sorted within categories
   - Visual separation with section headers

2. **Direct Feed Access**
   - Click any feed to see its articles
   - No need to navigate through multiple screens
   - Immediate access to content

3. **Feed Management**
   - "Manage Feeds" option in sidebar
   - Add, remove, and organize feeds
   - Import/export OPML

4. **Persistent Navigation**
   - Sidebar remains visible while browsing
   - Easy switching between feeds
   - Context is maintained

5. **Search Capability**
   - Each feed view includes search
   - Filter articles by title or description
   - Real-time search results

## Benefits

### For Users
- **Efficient Navigation**: Quick access to all feeds from sidebar
- **Better Space Utilization**: iPad screen is used effectively
- **Familiar Patterns**: Follows standard iPad/Mac app conventions
- **Improved Productivity**: Less tapping to access content

### For Developers
- **SwiftUI Native**: Uses built-in NavigationSplitView
- **Maintainable**: Separate views for iPhone and iPad layouts
- **Scalable**: Easy to add new sidebar items or sections
- **Type-Safe**: Uses enums and PersistentIdentifier for navigation

## Compatibility

- **iOS 18.0+**: Required for NavigationSplitView and SwiftData
- **iPhone**: Maintains existing tab bar experience
- **iPad**: New sidebar experience
- **Mac Catalyst**: Automatically supports sidebar (if enabled)

## Future Enhancements

Potential improvements for future releases:

1. **Drag and Drop**: Reorder feeds in sidebar
2. **Custom Categories**: Create and manage custom feed categories
3. **Sidebar Customization**: Show/hide certain sections
4. **Feed Icons**: Display feed favicons in sidebar
5. **Unread Counts**: Show unread article counts per feed
6. **Quick Actions**: Right-click context menus for feeds
7. **Keyboard Navigation**: Full keyboard support for sidebar

## Testing

To test the sidebar feature:

1. **iPhone Simulator**: Should show tab bar at bottom
2. **iPad Simulator**: Should show sidebar on left
3. **Window Resizing**: Test size class transitions
4. **Feed Selection**: Verify navigation works correctly
5. **Audio Player**: Ensure mini player works in both layouts

## Code Review Notes

- ✅ Size class detection using `@Environment(\.horizontalSizeClass)`
- ✅ Separate view components for different layouts
- ✅ Proper use of SwiftData queries and relationships
- ✅ Type-safe navigation using enums
- ✅ Stable feed references using PersistentIdentifier
- ✅ Maintains existing functionality on iPhone
- ✅ Follows SwiftUI best practices
- ✅ No breaking changes to existing code
