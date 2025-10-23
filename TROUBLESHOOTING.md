# Troubleshooting Navigation and Display Issues

## Issue: Can't Click Articles or Styling is Gone

If you're experiencing issues with navigation or text display, try these steps:

### Step 1: Clean Build
```bash
# In Xcode:
1. Press Shift+Cmd+K (Clean Build Folder)
2. Press Cmd+B (Build)
3. Press Cmd+R (Run)
```

### Step 2: Check Console for Errors

When you tap an article, look at Xcode's console (bottom panel). If you see errors like:
- "Failed to find model"
- "Cannot convert value"
- Any red error messages

This helps identify the issue.

### Step 3: Clear Data and Re-sync

The old cached articles might be causing issues:

1. Go to **Feeds** tab
2. Tap **menu (⋯)** → **Clear All Data**
3. Re-add your RSS feeds
4. Let them sync
5. Try viewing articles again

### Step 4: Verify Files are Added to Xcode

Make sure these files are in your Xcode project (not red in Project Navigator):

- ✅ `Utilities/HTMLHelper.swift`
- ✅ `Utilities/DatabaseHelper.swift`
- ✅ `Views/ArticleWebView.swift`
- ✅ `Views/TodayView.swift` (updated)

### Step 5: Check Target Membership

1. Select any of the above files in Project Navigator
2. Look at the right panel (File Inspector)
3. Under "Target Membership", ensure **"Today"** is checked

## Specific Issues

### "Text has no formatting/bold/italic"

The HTML parser successfully stripped tags but also removed formatting:

**Fix:** Clear data and re-sync. The new parser should preserve formatting.

**Check:** Look at the article description in the list. Do you see:
- Bold text for important words? ✅ Good
- Plain text only? ❌ Parser fell back to stripping
- HTML tags like `<span>`? ❌ Parser failed

### "Can't tap on articles at all"

**Possible causes:**

1. **Navigation stack broken**: Try force-quitting the app and relaunching
2. **Model context issue**: Clear all data
3. **View hierarchy problem**: Check console for errors

**Debug steps:**
```swift
// Temporarily add this to ArticleRowView to test if taps work:
.onTapGesture {
    print("Article tapped: \(article.title)")
}
```

If you see the print but navigation doesn't work, it's a NavigationStack issue.

### "App crashes when opening article"

Check the crash log in Xcode console. Common issues:

1. **"Cannot find Article in context"**: Clear data and re-sync
2. **"nil unwrapping"**: The article might be deleted
3. **"WebView error"**: URL might be invalid

## Quick Reset

If nothing works, do a full reset:

1. **Stop the app** (Cmd+. in Xcode)
2. **Delete the app** from simulator (long-press → Remove App)
3. **Clean build folder** (Shift+Cmd+K)
4. **Build and run** (Cmd+R)
5. **Add feeds fresh**

This ensures no cached data or stale state.

## Still Having Issues?

Please check:
1. **Xcode Console** - What errors appear?
2. **When tapping article** - Does anything happen? Brief flash? Nothing?
3. **Article list** - Do articles show up? Is text readable?
4. **After clearing data** - Can you add feeds and see new articles?

Share these details for more specific help!
