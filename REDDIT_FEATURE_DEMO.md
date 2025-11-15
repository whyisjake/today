# Reddit RSS Feed Support - Visual Demo

## Overview
This document demonstrates the Reddit RSS feed support features in the Today app.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Reddit RSS Feed                          │
│                  https://reddit.com/r/baseball.rss              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        RSSParser                                │
│  • Detects Reddit URL pattern                                   │
│  • Extracts subreddit from URL                                  │
│  • Extracts post ID from content/link                           │
│  • Extracts comments URL                                        │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Article Model                            │
│  Standard Fields:                                               │
│    • title, link, description, content                          │
│    • publishedDate, author, guid                                │
│                                                                  │
│  Reddit-Specific Fields (NEW):                                  │
│    • redditSubreddit: String?                                   │
│    • redditCommentsUrl: String?                                 │
│    • redditPostId: String?                                      │
│    • isRedditPost: Bool (computed)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        UI Components                            │
│                                                                  │
│  ArticleRowView:                                                │
│    ✓ Shows Reddit badge (🗨️ r/baseball) in orange             │
│    ✓ Displays subreddit name                                   │
│                                                                  │
│  ArticleDetailSimple:                                           │
│    ✓ Adds "Comments" button for Reddit posts                   │
│    ✓ Opens Reddit comments in WebView                          │
└─────────────────────────────────────────────────────────────────┘
```

## Example: Reddit Post Display

### Before (Regular RSS Feed)
```
┌──────────────────────────────────────────────────────┐
│ Article Title Here                                   │
│ This is the article description shown in the list... │
│                                                       │
│ 3h ago • TechCrunch                              📧  │
└──────────────────────────────────────────────────────┘
```

### After (Reddit RSS Feed)
```
┌──────────────────────────────────────────────────────┐
│ Yankees win the World Series!                        │
│ What an amazing game! The Yankees pulled off an...   │
│                                                       │
│ 2h ago • /r/baseball • 🗨️ r/baseball            📧  │
└──────────────────────────────────────────────────────┘
                              ↑
                    NEW: Reddit badge in orange
```

## Feature Comparison

| Feature | Regular Feed | Reddit Feed |
|---------|-------------|-------------|
| Article Title | ✅ | ✅ |
| Article Description | ✅ | ✅ |
| Feed Name | ✅ | ✅ |
| Subreddit Badge | ❌ | ✅ NEW |
| Comments Button | ❌ | ✅ NEW |
| Post ID Tracking | ❌ | ✅ NEW |
| Direct Comments Link | ❌ | ✅ NEW |

## User Journey

### 1. Adding a Reddit Feed
```
User enters: https://www.reddit.com/r/baseball.rss
              ↓
App detects: "This is a Reddit feed!"
              ↓
Extracted:   Subreddit = "baseball"
              ↓
Result:      Feed added with Reddit metadata
```

### 2. Viewing Articles
```
Article List
├── Regular Article (example.com)
│   └── Shows: Title, description, feed name
│
└── Reddit Post (reddit.com/r/baseball)
    └── Shows: Title, description, feed name, 🗨️ r/baseball
                                                  ↑
                                          Orange Reddit badge
```

### 3. Reading & Commenting
```
User taps article
    ↓
Article Detail Opens
    ↓
Bottom Toolbar:
[◀ Previous] [💬 Comments] [📄 Read] [Next ▶]
                    ↑
            NEW: Comments button
                    ↓
User taps "Comments"
    ↓
Reddit comments page opens in WebView
    ↓
User can read/browse comments
```

## Technical Implementation Details

### Detection Logic
```swift
// Feed level detection
var isRedditFeed: Bool {
    return url.contains("reddit.com/r/") && url.hasSuffix(".rss")
}

// Article level detection  
var isRedditPost: Bool {
    return redditSubreddit != nil || redditCommentsUrl != nil
}
```

### Metadata Extraction
```swift
// From URL: https://www.reddit.com/r/baseball/comments/abc123/title/
extractRedditMetadata(link: url)
    ↓
Returns:
- subreddit: "baseball"
- commentsUrl: "https://www.reddit.com/r/baseball/comments/abc123/..."
- postId: "t3_abc123"
```

### UI Rendering
```swift
// In ArticleRowView
if article.isRedditPost, let subreddit = article.redditSubreddit {
    HStack {
        Image(systemName: "bubble.left.and.bubble.right.fill")
        Text("r/\(subreddit)")
    }
    .foregroundStyle(.orange)
}

// In ArticleDetailSimple
if article.isRedditPost, let commentsUrl = article.redditCommentsUrl {
    NavigationLink {
        ArticleWebViewSimple(url: URL(string: commentsUrl)!)
    } label: {
        Label("Comments", systemImage: "bubble.left.and.bubble.right")
    }
}
```

## Testing Coverage

### Unit Tests
- ✅ Reddit feed detection
- ✅ Subreddit extraction from URLs
- ✅ Post ID extraction from content and links
- ✅ Comments URL extraction
- ✅ Non-Reddit feed handling (no metadata)
- ✅ Multiple Reddit posts in one feed

### Test Cases
1. **Standard Reddit feed**: `https://www.reddit.com/r/baseball.rss`
2. **Multiple subreddits**: `https://www.reddit.com/r/tech+programming.rss`
3. **Non-Reddit feed**: Should not extract Reddit metadata
4. **Edge cases**: Missing IDs, malformed URLs, etc.

## Browser Compatibility

The Reddit comment viewer uses the in-app `WKWebView`:
- ✅ Supports full Reddit web interface
- ✅ Handles Reddit's JavaScript
- ✅ Allows back/forward navigation
- ✅ Respects user's dark mode preference

## Privacy Considerations

- 🔒 All Reddit metadata stored locally (SwiftData)
- 🔒 No third-party tracking
- 🔒 Comments loaded in isolated WebView
- 🔒 No Reddit authentication required
- 🔒 No data sent to Reddit servers (except when viewing content)

## Future Enhancements

Potential improvements:
1. **Vote counts**: Display upvotes/downvotes if available in feed
2. **Comment counts**: Show number of comments from feed metadata
3. **Flair support**: Extract and display Reddit flair tags
4. **User profiles**: Support for user RSS feeds
5. **Sorting options**: Allow filtering by hot/new/top/controversial
6. **Cross-posting**: Detect and display cross-posted content
