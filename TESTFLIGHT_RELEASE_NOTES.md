# TestFlight Beta Release Notes

## Version 1.4.0 (Build 7)
**Release Date:** November 15, 2025

---

## 🎉 What's New

### Reddit RSS Support
**Add Reddit feeds directly to your reader!**
- **Simplified feed picker** - Choose between RSS Feed or Reddit when adding new feeds
- **Just enter the subreddit name** - No need for full URLs (e.g., just type "politics" not "r/politics")
- **Animated GIF/video playback** - Reddit posts with animated content play automatically
- **Gallery support** - Browse through multi-image Reddit posts with zoom and pan gestures
- **Comments view** - Read Reddit comments directly in the app
- **Author display** - See post authors in list view instead of feed names
- **Newsletter integration** - Reddit posts work seamlessly in generated newsletters

### Feed Navigation Improvements
**Tap feeds to view their articles!**
- **Tap a feed** → Opens a list of articles from that feed (unread by default)
- **Swipe or long-press** → Access edit/delete options
- Added **unread count badges** to feed list
- Feed article view includes mark all as read and show/hide read toggle

### Category Filter Enhancements
**Smarter, cleaner category buttons**
- Categories now show in **title case** (General, Work, Tech, etc.)
- **Hide empty categories** - Only categories with articles in the current time window appear
- **Preserve custom category case** - Your custom category names stay exactly as you set them
- **One-time migration** - Existing feeds automatically updated to consistent capitalization

### UI Polish
- Improved category button layout and styling
- Better visual consistency across the app
- Smoother navigation between feeds and articles

---

## 🧪 What to Test

### Priority: Reddit RSS Support
- [ ] **Add a Reddit feed** → Tap "+" → Select "Reddit" → Enter subreddit name (e.g., "technology")
- [ ] **View Reddit posts** → Should show with author name instead of feed title
- [ ] **Open a Reddit post** → Should see post content, images/videos, and comments button
- [ ] **Animated GIFs** → Should auto-play and loop smoothly
- [ ] **Gallery posts** → Swipe through multiple images, tap to zoom/pan
- [ ] **Comments** → Tap comments button → Should load and display Reddit comments
- [ ] **Newsletter with Reddit** → Generate newsletter from Reddit feed → Tap post → Should open in Reddit view
- [ ] **Navigation** → Use Previous/Next buttons to navigate between posts

### Priority: Feed Navigation
- [ ] **Tap a feed** in the Feeds tab → Should open that feed's articles
- [ ] Check the **unread count badge** on feed rows
- [ ] **Swipe left** on a feed → Edit/Delete buttons appear
- [ ] **Long-press** a feed → Context menu with Edit/Delete
- [ ] In feed articles view, **swipe articles** to mark as read/unread
- [ ] Tap **"Mark All as Read"** button
- [ ] Toggle **"Show Read"** to see all articles from that feed

### Priority: Category Filters
- [ ] Check category buttons at top of Today view
- [ ] Categories should be title-cased: **"All", "General", "Work", "Tech", etc.**
- [ ] Only categories with articles should appear
- [ ] Tap different categories to filter articles
- [ ] Scroll down to load more days → More categories may appear
- [ ] Custom category names should keep their original capitalization

### General Testing
- [ ] **Add new feed** → Should default to "General" category
- [ ] **Edit existing feed** → Category picker shows title-cased options
- [ ] **Import OPML** → Categories preserved or defaulted properly
- [ ] **Pull to refresh** → New articles appear correctly
- [ ] **Search articles** → Still works across all categories
- [ ] **AI Summary** → Still generates properly
- [ ] **Background sync** → Feeds update in background

---

## 🐛 Known Issues

### Context Window Overflow (AI Newsletter)
- Occasionally when generating newsletters with many articles, the AI may hit context limits
- **Workaround:** Generate newsletter with fewer articles, or retry
- Does not affect article summaries or chat features
- Fix planned for future release

### iPad Layout
- App runs in iPhone compatibility mode on iPad
- Layout not optimized for iPad screen sizes yet
- Full iPad support planned for future release

### Background Sync Timing
- iOS controls when background sync actually runs (for battery optimization)
- May not sync exactly on schedule
- This is expected iOS behavior

---

## 💬 Feedback We Need

### Feed Navigation
- Does tapping a feed to see its articles feel natural?
- Is the swipe vs. tap behavior clear?
- Are unread count badges helpful?
- Should we show read articles by default, or keep unread-only?

### Category Improvements
- Are title-cased categories easier to read? (General vs. general)
- Do you like that empty categories are hidden?
- Any issues with custom category names?

### Overall Experience
- Any performance issues with large feeds (100+ articles)?
- Does the app feel snappier or slower than previous versions?
- Any unexpected behaviors or crashes?
- Missing features you'd like to see?

---

## 📝 How to Report Issues

### In TestFlight App
1. Open TestFlight
2. Select "Today"
3. Tap "Send Beta Feedback"
4. Include:
   - What you were doing
   - What happened vs. what you expected
   - Screenshots if helpful

### Via GitHub
Create an issue at: https://github.com/whyisjake/today/issues

Include:
- iOS version (Settings → General → About → Software Version)
- Device model (iPhone 15, 17 Pro, etc.)
- Steps to reproduce
- Screenshots/screen recording if possible

---

## 🔄 Update Instructions

### First Time Installing
1. Tap the TestFlight link in your email/message
2. Install "Today" from TestFlight
3. Open the app and add some RSS feeds
4. Explore the features!

### Updating from Previous Beta
1. Open TestFlight app
2. Find "Today" in your apps list
3. Tap "Update" if available
4. Launch the app - **one-time migration will run** on first launch
   - This updates your existing feed categories (takes < 1 second)
   - You'll see "Category migration completed" in console logs
5. Your feeds, articles, and settings are preserved

---

## ⚙️ What Happens on First Launch

When you update to this version, a **one-time migration** runs automatically:
- Updates predefined lowercase categories to title case
  - "general" → "General"
  - "work" → "Work"
  - "tech" → "Tech"
  - etc.
- **Custom categories stay unchanged**
- Takes less than 1 second
- Only runs once (never repeats)
- Safe and reversible (edit feeds manually if needed)

You'll see this in logs:
```
Category migration already completed, skipping
```
(On subsequent launches)

---

## 🎯 Testing Focus Areas

### High Priority
1. **Feed list tap behavior** - This is the biggest change
2. **Category button visibility** - Make sure they appear/hide correctly
3. **Migration success** - All existing feeds should work normally

### Medium Priority
4. Article reading flow (should be unchanged)
5. AI features (summary, chat, newsletter)
6. Search and filtering
7. Background sync

### Low Priority
8. Settings and preferences
9. OPML import/export
10. Visual polish and animations

---

## 📊 Technical Details (For Curious Testers)

### What's Under the Hood
- **iOS 18.0+** required (down from iOS 26.0 beta requirement)
- **Apple Intelligence** on iOS 26+ for enhanced AI features
- **SwiftData** for local-only data storage
- **Migration system** for safe schema updates
- All processing happens **on-device** (privacy-first)

### Performance Targets
- Cold launch: < 3 seconds
- Article list scroll: 60fps
- Feed sync: < 10 seconds for typical feeds
- Memory usage: < 100MB typical

---

## 🙏 Thank You!

Your testing and feedback are invaluable. Every bug report, suggestion, and bit of feedback helps make Today better for everyone.

Special thanks to:
- **Jonathan Desrosiers** for reporting category capitalization issues
- All beta testers for ongoing feedback
- The RSS community for keeping the open web alive

---

## 📱 Need Help?

- **Documentation:** Check TROUBLESHOOTING.md in the GitHub repo
- **Questions:** Open a discussion on GitHub
- **Urgent issues:** Email jake@jakespurlock.com

Happy testing! 🚀

---

**Build Info:**
- Version: 1.4.0
- Build: 7
- Branch: main
- Commit: [Latest]
