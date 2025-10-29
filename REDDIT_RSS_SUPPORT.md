# Reddit RSS Feed Support

The Today app now includes special handling for Reddit RSS feeds, providing an enhanced experience when subscribing to subreddit feeds.

## Features

### Reddit Feed Detection
- Automatically detects when a feed URL is from Reddit (e.g., `https://www.reddit.com/r/baseball.rss`)
- Extracts subreddit information from the feed URL

### Enhanced Article Metadata
For articles from Reddit feeds, the app extracts and stores:
- **Subreddit name**: The subreddit the post is from (e.g., "baseball")
- **Comments URL**: Direct link to the Reddit comments page
- **Post ID**: Reddit's unique post identifier (e.g., "t3_abc123")

### UI Enhancements

#### Article List View
- Shows a distinctive Reddit badge with the subreddit name (e.g., "r/baseball")
- Uses an orange accent color for Reddit posts to make them easily identifiable
- Displays a comment bubble icon next to the subreddit name

#### Article Detail View
- Adds a **"Comments"** button in the bottom toolbar for Reddit posts
- Tapping the Comments button opens the Reddit comments page in the in-app browser
- Allows users to quickly switch between reading the article and viewing Reddit discussions

## How to Use

### Subscribe to a Reddit Feed
1. Open the Feeds tab in the app
2. Tap the "+" button to add a new feed
3. Enter a Reddit RSS feed URL (e.g., `https://www.reddit.com/r/baseball.rss`)
4. The app will automatically detect it's a Reddit feed and apply special handling

### View Reddit Comments
1. Open any article from a Reddit feed
2. Look for the **"Comments"** button in the bottom toolbar
3. Tap the button to view the Reddit discussion thread

### Identify Reddit Posts
Reddit posts are easy to identify in the article list:
- Look for the orange badge showing the subreddit name (e.g., "r/baseball")
- The badge appears next to the feed title in the article metadata

## Technical Details

### Data Model
The `Article` model has been extended with three optional Reddit-specific fields:
- `redditSubreddit: String?` - The subreddit name
- `redditCommentsUrl: String?` - Direct URL to the Reddit comments
- `redditPostId: String?` - Reddit's post identifier

The `Feed` model includes computed properties:
- `isRedditFeed: Bool` - Returns true if the feed is from Reddit
- `redditSubreddit: String?` - Extracts the subreddit from the feed URL

### Parsing Logic
The `RSSParser` automatically extracts Reddit metadata during feed parsing:
1. Detects Reddit URLs using regex pattern matching
2. Extracts subreddit name from the link URL
3. Identifies the comments URL (typically the same as the link)
4. Extracts the post ID from either the content or link

### UI Components
Reddit-specific UI elements are conditionally displayed:
- `ArticleRowView`: Shows Reddit badge when `article.isRedditPost` is true
- `ArticleDetailSimple`: Shows Comments button when `article.redditCommentsUrl` is available

## Supported Reddit Feed Formats

The app supports Reddit RSS feeds in both RSS 2.0 and Atom formats:
- Standard subreddit feeds: `https://www.reddit.com/r/{subreddit}.rss`
- Multi-reddit feeds: `https://www.reddit.com/r/{sub1}+{sub2}+{sub3}.rss`

## Examples

### Popular Subreddit Feeds
- Baseball: `https://www.reddit.com/r/baseball.rss`
- Technology: `https://www.reddit.com/r/technology.rss`
- Programming: `https://www.reddit.com/r/programming.rss`
- News: `https://www.reddit.com/r/news.rss`
- World News: `https://www.reddit.com/r/worldnews.rss`

## Future Enhancements

Potential future improvements for Reddit feed support:
- Display upvote/downvote counts if available in the feed
- Show number of comments from the feed metadata
- Add support for sorting options (hot, new, top, etc.)
- Extract and display Reddit flair tags
- Support for user feeds (e.g., `https://www.reddit.com/user/{username}.rss`)
