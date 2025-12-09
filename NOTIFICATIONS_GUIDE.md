# Feed Notifications Guide

Today supports smart notifications for new articles from your RSS feeds. Notifications are intelligently grouped and summarized using on-device AI to reduce notification spam while keeping you informed.

## Features

### Per-Feed Control
- Enable or disable notifications for individual feeds
- Default: notifications are disabled for all feeds
- Easy toggle via context menu or settings

### Smart Grouping
When multiple new articles arrive from the same feed during a background sync:
- **Single Article**: Shows article title and description
- **Multiple Articles**: Groups them into one notification with an AI-generated summary
- Reduces notification spam while providing meaningful context

### AI Summarization
- Uses Apple's on-device AI (iOS 26+) or NaturalLanguage framework (iOS 18-25)
- Generates concise summaries of multiple articles
- Privacy-first: All processing happens on your device
- No data leaves your device

### Background Sync Integration
- Notifications are posted during automatic background syncs
- Syncs occur approximately every hour (controlled by iOS)
- Only new articles trigger notifications

## Setup

### 1. Grant Notification Permission
When you first open the app, you'll be prompted to allow notifications. You can also:
1. Open Settings app
2. Find "Today" in the apps list
3. Tap "Notifications"
4. Enable "Allow Notifications"

### 2. Enable Notifications for Feeds

#### Method 1: Context Menu (Quick)
1. Go to the Feeds tab
2. Long-press on a feed
3. Tap "Enable Notifications" (or "Disable Notifications" if already enabled)
4. Look for the bell icon 🔔 next to feeds with notifications enabled

#### Method 2: Settings (Detailed)
1. Open Settings tab
2. Tap "Notification Settings"
3. View notification authorization status
4. Toggle notifications for each feed individually

## How It Works

### Notification Flow
```
Background Sync Runs
    ↓
New Articles Detected
    ↓
Feed Has Notifications Enabled?
    ↓ Yes
Single Article?
    ↓ Yes          ↓ No (Multiple)
Simple             AI Summarization
Notification       Generated
    ↓                  ↓
Notification Posted
```

### Notification Content

#### Single Article Notification
- **Title**: Feed name (e.g., "TechCrunch")
- **Body**: Article title
- **Subtitle**: Article description preview (up to 100 characters)

#### Grouped Notification (Multiple Articles)
- **Title**: Feed name
- **Body**: "📰 X new articles"
- **Subtitle**: AI-generated summary of all articles

### Examples

**Single Article:**
```
TechCrunch
New AI Model Breaks Records
OpenAI's latest release achieves state-of-the-art performance on...
```

**Multiple Articles (with AI summary):**
```
TechCrunch
📰 5 new articles
Major developments in AI include new models, regulatory updates, and startup funding rounds
```

## Settings

### Notification Settings View
Access via Settings → Notification Settings

**Displays:**
- ✅ **Permission Status**: Shows if notifications are authorized
- 🔔 **Feed List**: Toggle notifications for each feed
- 🗑️ **Clear All**: Remove all delivered notifications

**Status Indicators:**
- 🟢 Green checkmark: Notifications enabled
- 🔴 Red X: Notifications denied (tap "Settings" to enable)
- 🟠 Orange question mark: Permission not requested

### Feed List Indicators
In the Feeds tab, each feed shows:
- 🔔 **Bell icon**: Notifications are enabled for this feed
- No icon: Notifications are disabled

## Privacy & Security

### On-Device Processing
- All AI summarization happens on your device
- No article content is sent to external servers
- Notification generation uses the same AIService as in-app summaries

### What's Stored
- Feed notification preference (enabled/disabled)
- No notification history is stored
- Notifications are handled by iOS

### Permissions Required
- **Notifications**: Required to display alerts
- **Background App Refresh**: Required for automatic syncing (optional)

## Troubleshooting

### Not Receiving Notifications?

#### Check Authorization Status
1. Go to Settings → Notification Settings
2. Verify status is "Notifications are enabled"
3. If denied, tap "Settings" to open system settings

#### Verify Feed Settings
1. Go to Feeds tab
2. Check for bell icon 🔔 on your feed
3. If missing, enable via context menu

#### Check Background Refresh
1. Open iOS Settings
2. Go to General → Background App Refresh
3. Ensure "Background App Refresh" is on
4. Ensure "Today" is enabled

### Notifications Not Grouping?

Notification grouping happens when:
- Multiple new articles arrive during the same sync
- All articles are from the same feed
- Feed has notifications enabled

If you only see individual notifications:
- This is normal if articles arrive one at a time
- iOS controls when background syncs occur
- Grouping happens automatically when conditions are met

### AI Summaries Not Appearing?

AI summaries require:
- iOS 26+ for Apple Intelligence
- Falls back to simple article list on older versions
- Check device compatibility in Settings → AI Summary

## Best Practices

### Recommended Setup
- Enable notifications for 3-5 important feeds
- Avoid enabling for all feeds (prevents notification overload)
- Use categories to organize feeds (only enable notifications for critical categories)

### Managing Notification Volume
- Start with fewer feeds enabled
- Monitor notification frequency
- Disable feeds that post too frequently
- Use the "Clear All" button to clean up old notifications

### Testing Notifications
1. Enable notifications for a frequently updated feed (e.g., news site)
2. Wait for next background sync (up to 1 hour)
3. Check notification center for new notifications
4. Verify grouping when multiple articles arrive

## Technical Details

### Notification Types
- **Single**: Posted for one new article
- **Grouped**: Posted for 2+ new articles from same feed
- Both use thread identifiers for iOS-level grouping

### Deep Linking (Future Feature)
Notifications include metadata for deep linking:
- Feed ID
- Article ID(s)
- Notification type

*Note: Tap handling will be implemented in a future update*

### Background Sync Schedule
- Managed by iOS BGTaskScheduler
- Minimum 15 minutes between syncs
- Actual timing controlled by iOS based on usage patterns
- App must be installed and permission granted

## FAQ

**Q: Can I customize notification sounds?**
A: Not currently. Notifications use the default system sound.

**Q: Will I get notifications for articles I've already read?**
A: No. Only unread articles from enabled feeds trigger notifications.

**Q: Can I schedule quiet hours?**
A: Use iOS Focus modes or Scheduled Summary to manage notification timing.

**Q: Do notifications work in airplane mode?**
A: No. Background sync requires internet connection.

**Q: How many notifications will I get per sync?**
A: One notification per feed with new articles (automatically grouped).

**Q: Can I get notifications for specific keywords?**
A: Not currently. Notifications are feed-level only.

## Roadmap

Planned improvements:
- [ ] Tap to open article directly
- [ ] Notification action buttons (Mark as Read, Open)
- [ ] Keyword-based filtering
- [ ] Scheduled quiet hours (in-app)
- [ ] Notification history view
- [ ] Custom notification sounds per feed

## Related Documentation

- [Background Sync Setup](BACKGROUND_SETUP.md) - Configure background refresh
- [Privacy Policy](PRIVACY.md) - Data handling and privacy
- [Troubleshooting Guide](TROUBLESHOOTING.md) - General app issues
- [Testing Plan](TESTING_PLAN.md) - Test notification features

## Support

If you encounter issues:
1. Check this guide first
2. Review [Troubleshooting Guide](TROUBLESHOOTING.md)
3. File an issue on GitHub
4. Contact support via App Store listing

---

**Version**: 1.3.0+
**Last Updated**: December 2025
**Platform**: iOS 18.0+
