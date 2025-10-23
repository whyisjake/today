# How to Clear Cached RSS Data

## Why You Need This

When we added HTML rendering, your RSS articles were already synced and stored in the database with the raw HTML. The new HTML rendering only affects how it's *displayed*, not what's already *stored*.

To see properly formatted content, you need to clear the old data and re-sync.

## Option 1: Use the Built-in Clear Button (Easiest)

I just added a "Clear All Data" button to the app:

1. Open the app
2. Go to the **"Feeds"** tab
3. Tap the **menu button** (three dots in a circle) in the top-left
4. Tap **"Clear All Data"** (red option at the bottom)
5. This will delete all feeds and articles
6. Re-add your RSS feeds using the "+" button
7. They'll sync with the new HTML rendering

## Option 2: Delete Individual Feeds

If you only want to refresh specific feeds:

1. Go to the **"Feeds"** tab
2. Swipe left on any feed
3. Tap **"Delete"**
4. Re-add the feed with the "+" button
5. It will fetch fresh articles with HTML rendering

## Option 3: Delete and Reinstall App (Nuclear Option)

This completely resets everything:

1. Long-press the Today app icon on your home screen
2. Tap "Remove App" → "Delete App"
3. Re-run the app from Xcode (Cmd+R)
4. Add your feeds fresh

## Verifying HTML Rendering Works

After clearing and re-syncing, you should see:

**Before (raw HTML):**
```
<p>This is a <strong>great</strong> article</p>
```

**After (formatted):**
```
This is a great article
```
(with "great" appearing bold)

## Files to Add First

Make sure you've added these new files to your Xcode project:

✅ `Utilities/HTMLHelper.swift` - HTML conversion
✅ `Utilities/DatabaseHelper.swift` - Data clearing utility
✅ `Views/ArticleWebView.swift` - In-app reader

**How to add them:**
1. Right-click "Today" folder in Xcode
2. "Add Files to Today..."
3. Navigate to the Utilities and Views folders
4. Select the files
5. Make sure "Today" target is checked
6. Click "Add"

## Testing the Menu

The menu button (⋯ in circle) in the Feeds tab now has:
- **Sync All Feeds** - Refresh all articles
- **Clear All Data** - Delete everything (use this!)

## Troubleshooting

**"Still seeing HTML after clearing"**
- Make sure you added `HTMLHelper.swift` to the Xcode project
- Clean build: Shift+Cmd+K, then rebuild
- Check that the file isn't red in Project Navigator

**"Menu button doesn't show"**
- Make sure you updated `FeedListView.swift`
- The menu is in the top-left (not top-right)
- It's a circle with three dots icon

**"Clear All Data doesn't work"**
- Make sure you added `DatabaseHelper.swift` to Xcode
- Check the console for error messages
- Try the nuclear option (delete app)

## Quick Steps (TL;DR)

1. Add new files to Xcode project
2. Build and run (Cmd+R)
3. Go to Feeds tab
4. Tap menu (⋯) → Clear All Data
5. Re-add your RSS feeds
6. Enjoy formatted content! ✨

That's it! The cached data is now fresh and will display with proper HTML formatting.
