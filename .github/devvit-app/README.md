# Today RSS Feed Recommender - Devvit App

A community-powered RSS feed recommendation system for r/TodayRSS. Users can share their favorite feeds with structured information, making it easy for others to discover great content!

## What It Does

Adds a "📡 Recommend RSS Feed" menu item to r/TodayRSS that opens a form where users can:
- Submit feed name and URL
- Select a category (Tech, News, Gaming, etc.)
- Describe why they recommend it
- Automatically creates a formatted post with all the details

## Features

### For Users
- **Easy Submission**: Simple form accessible from the subreddit menu
- **13 Categories**: News, Tech, Gaming, Sports, Entertainment, Business, Science, Design, Mobile, World News, Podcasts, Blogs, Other
- **Formatted Posts**: Auto-formatted with emoji, category, feed URL, and description
- **Copy-Paste Ready**: Feed URLs are formatted for easy copying into Today app
- **Success Feedback**: Toast notification confirms successful submission

### For Moderators
- **Organized Content**: Consistent post format makes moderation easier
- **Auto-Flaired**: Posts tagged with "📰 Feed Recommendation" flair (if configured)
- **Community Building**: Encourages engagement and content sharing
- **Quality Control**: Required fields ensure complete information

## Setup Instructions

### 1. Install Devvit CLI

```bash
npm install -g devvit
```

### 2. Login to Reddit

```bash
devvit login
```

### 3. Navigate to the App Directory

```bash
cd .github/devvit-app
```

### 4. Install Dependencies

```bash
npm install
```

### 5. Test Locally (Optional)

```bash
npm run dev
```

Visit the local dev URL to test the form.

### 6. Upload to Reddit

```bash
npm run upload
```

### 7. Install on r/TodayRSS

1. Go to https://developers.reddit.com/apps
2. Find "Today RSS Feed Recommender"
3. Click "Install"
4. Select r/TodayRSS
5. Approve permissions (submit, flair)

### 8. Configure Post Flair (Optional but Recommended)

1. Go to r/TodayRSS mod tools
2. Navigate to Post Flair settings
3. Create a flair with text: "📰 Feed Recommendation"
4. The app will auto-apply this flair to recommendations

## How Users Access It

Once installed, users will see "📡 Recommend RSS Feed" in two places:

1. **Subreddit Menu** (3 dots on desktop, menu on mobile)
2. **Mod Tools** (for moderators)

Clicking it opens the submission form!

## Example Post Format

**Title:**
```
💻 Feed Recommendation: The Verge
```

**Body:**
```markdown
## The Verge

**Category:** Technology

**Feed URL:** https://www.theverge.com/rss/index.xml

**Why I recommend it:**
Great coverage of tech news, gadgets, and reviews. Updates multiple times daily with in-depth articles and breaking news.

---

*Want to add this feed to Today? Copy the feed URL above and add it in the app!*

*Have a feed to recommend? Click "Recommend RSS Feed" to share your favorite!*
```

## Categories Available

- 📰 News
- 💻 Technology
- 🎮 Gaming
- ⚽ Sports
- 🎬 Entertainment
- 💼 Business
- 🔬 Science
- 🎨 Design
- 📱 Mobile
- 🌍 World News
- 🎧 Podcasts
- 📚 Blogs
- 🔮 Other

## Benefits

### Community Engagement
- **Low Barrier**: Easy for anyone to contribute
- **Valuable Content**: Builds a curated feed library
- **Social Proof**: Community votes on recommendations
- **Discovery**: New users find quality feeds quickly

### Content Quality
- **Structured Data**: Consistent format for all submissions
- **URL Validation**: Ensures proper feed URLs
- **Required Fields**: No incomplete submissions
- **Categorization**: Easy browsing by topic

### App Promotion
- **Shows Value**: Demonstrates what Today can do
- **User Generated**: Community creates the content
- **Engagement Loop**: Users find feeds → add to Today → share more feeds
- **Resource Building**: Creates a valuable community asset

## Updating the App

Make changes to `src/main.ts` and run:

```bash
npm run upload
```

The app updates instantly on Reddit!

## Common Use Cases

1. **New User Onboarding**: "What feeds should I start with?"
2. **Topic Discovery**: "Show me all the Tech feeds people love"
3. **Community Building**: "Share your favorite niche feed"
4. **Resource Creation**: Export to OPML file (future feature)
5. **Quality Curation**: Upvote the best recommendations

## Future Enhancements

Ideas for v2:
- Export all recommendations to OPML file
- Search/filter recommendations by category
- Leaderboard of most-recommended feeds
- Integration with GitHub to auto-update feed list
- Duplicate detection
- Feed validation (check if URL actually works)

## Troubleshooting

**"📡 Recommend RSS Feed" doesn't appear:**
- Make sure the app is installed on r/TodayRSS
- Check you have the latest version
- Try refreshing Reddit

**Form submission fails:**
- Check the feed URL starts with http:// or https://
- Ensure all required fields are filled
- Check Devvit logs: `devvit logs`

**Flair not applied:**
- Create the "📰 Feed Recommendation" flair in mod tools
- Ensure the app has flair permissions
- Flair is optional - posts work without it

## Support

- Devvit Docs: https://developers.reddit.com/docs
- Devvit Discord: https://discord.gg/devvit
- Issues: File on the GitHub repository

## License

MIT
