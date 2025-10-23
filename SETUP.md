# Setup Instructions for Today RSS Reader

I've created all the necessary code files for your RSS reader app with AI summarization. However, since I created files outside of Xcode, you'll need to add them to your Xcode project manually.

## Files Created

### Models (Today/Models/)
- `Feed.swift` - RSS feed subscriptions
- `Article.swift` - Individual articles from feeds

### Services (Today/Services/)
- `RSSParser.swift` - RSS feed parsing logic
- `FeedManager.swift` - Feed subscription management and syncing
- `AIService.swift` - Local AI summarization using Apple's NaturalLanguage framework
- `BackgroundSyncManager.swift` - Background fetch for automatic updates

### Views (Today/Views/)
- `TodayView.swift` - Main view showing recent articles with category filtering
- `FeedListView.swift` - Manage RSS feed subscriptions
- `AIChatView.swift` - Chat interface for AI summaries

### Updated Files
- `TodayApp.swift` - Updated to use new data models and background sync
- `ContentView.swift` - Updated to use tab-based navigation

## Adding Files to Xcode Project

1. **Open the project in Xcode:**
   ```bash
   open Today.xcodeproj
   ```

2. **Add the new files:**
   - Right-click on the "Today" folder in Xcode's Project Navigator
   - Select "Add Files to Today..."
   - Navigate to the Today folder and:
     - Add the `Models` folder
     - Add the `Services` folder
     - Add the `Views` folder
   - Make sure "Copy items if needed" is UNCHECKED (files are already in the right location)
   - Make sure "Today" target is checked
   - Click "Add"

3. **Configure Background Modes:**
   - Select the Today project in Project Navigator
   - Select the "Today" target
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "Background Modes"
   - Check "Background fetch"

4. **Update Info.plist:**
   - Add this key to enable background tasks:
   - Key: `Permitted background task scheduler identifiers`
   - Type: Array
   - Add item: `com.today.feedsync`

## Testing the App

You can now build and run the app:

```bash
# Open in Xcode and press Cmd+R to run
open Today.xcodeproj
```

Or use command line:
```bash
# List available simulators
xcrun simctl list devices available

# Build for a specific simulator (replace with your device)
xcodebuild -project Today.xcodeproj -scheme Today -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

## Getting Started with the App

1. **Add RSS Feeds:**
   - Go to the "Feeds" tab
   - Tap the "+" button
   - Enter an RSS feed URL (try these):
     - Daring Fireball: `https://daringfireball.net/feeds/main`
     - Hacker News: `https://news.ycombinator.com/rss`
     - The Verge: `https://www.theverge.com/rss/index.xml`

2. **View Articles:**
   - Go to the "Today" tab
   - Browse articles from the last 7 days
   - Filter by category using the buttons at the top
   - Swipe left to favorite, swipe right to mark as read

3. **Chat with AI:**
   - Go to the "AI Summary" tab
   - Ask questions like:
     - "Summarize today's articles"
     - "What should I read?"
     - "What are the trending topics?"

## Features Implemented

✅ RSS feed management (add/remove feeds with categories)
✅ Automatic feed syncing
✅ Today view with last 7 days of articles
✅ Category/thread filtering (work, social, tech, etc.)
✅ AI-powered content summarization using Apple's NaturalLanguage framework
✅ Chat interface for interacting with AI
✅ Background sync capability (syncs feeds in the background)
✅ Mark articles as read/favorite
✅ Search functionality

## Notes

- **AI Model**: Currently uses Apple's built-in NaturalLanguage framework for basic text analysis and keyword extraction. For more advanced AI features, you could integrate:
  - Core ML models
  - MLX Swift for on-device LLMs
  - OpenAI API (requires internet)

- **Background Sync**: iOS limits background fetch to preserve battery. The app will attempt to sync every hour, but iOS controls when this actually happens.

- **Testing Background Sync**: In Xcode, you can simulate background fetch:
  - Run the app
  - Go to Debug menu > Simulate Background Fetch

## Troubleshooting

If you get build errors:
1. Make sure all files are added to the Today target
2. Check that file references are correct (not red in Project Navigator)
3. Clean build folder: Shift+Cmd+K
4. Try closing and reopening Xcode
