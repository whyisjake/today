# Beta Testing Guide - Today v1.2

Thank you for helping test Today v1.2! This version includes major new AI features and improvements. Your feedback is crucial for ensuring a smooth App Store release.

## What's New in v1.2

### 🤖 AI-Powered Newsletter Generation (NEW!)
- Smart newsletter intros with witty, personalized writing
- Progressive loading with streaming content generation
- AI-generated titles and subtitles

### 🧠 Apple Intelligence Integration (NEW!)
- On-device AI summaries using Apple's Language Model (iOS 26+ only)
- Intelligent article selection for analysis
- Privacy-focused local processing

### 📝 Typography Improvements
- WordPress-style smart quotes and typography
- Better text rendering with proper spacing around quotes
- Fixed HTML entity handling

### 🎨 UI/UX Enhancements
- Day-based pagination for browsing articles
- Share button in article detail view
- External link indicators for minimal content
- Improved navigation and performance

### 🔐 Security Updates
- Enhanced web authentication with SFSafariViewController
- Better passkey and security key support

## Priority Testing Areas

### ⭐ Critical - Must Test

#### 1. AI Newsletter Generation
**How to test:**
1. Go to the AI Summary tab
2. Scroll down to the newsletter section
3. Tap "Generate Newsletter Intro"
4. Watch for progressive loading (should see content appear gradually)
5. Check if the intro is witty, relevant, and complete (no follow-up questions asking for help)

**What to look for:**
- ✅ Content loads progressively (streams in)
- ✅ Title and subtitle are clever and relevant
- ✅ Intro paragraph flows naturally
- ✅ NO questions like "Would you like help writing more?"
- ❌ App crashes or freezes
- ❌ Blank or error messages
- ❌ Content that seems inappropriate or off-topic

**iOS 26+ Only: Apple Intelligence**
- If you're on iOS 26+, test the AI summary feature
- It should use on-device processing (faster, more private)
- Check if summaries are coherent and relevant

#### 2. Typography & Text Rendering
**How to test:**
1. Browse your article list
2. Look for titles with quotes, apostrophes, or dashes
3. Open articles and check descriptions

**What to look for:**
- ✅ Smart quotes: "quoted text" and 'single quotes'
- ✅ Proper spacing around quotes (e.g., "Biden Decries 'Dark Days' Under Trump")
- ✅ Em dashes (—) instead of double hyphens (--)
- ❌ Missing spaces around quotes
- ❌ Weird characters or boxes (□)
- ❌ Double spaces or collapsed words

**Test cases to look for:**
- Article titles with HTML entities
- Quotes at the start/end of titles
- Apostrophes in contractions (don't, it's, can't)
- Measurements with feet/inches (5'10", 3' board)

#### 3. Day-Based Pagination
**How to test:**
1. Go to the Today tab
2. Scroll through your articles
3. Notice section headers by date (Today, Yesterday, 2 days ago, etc.)

**What to look for:**
- ✅ Articles grouped by publication day
- ✅ Smooth scrolling
- ✅ Dates make sense
- ❌ Articles in wrong date sections
- ❌ Missing date headers
- ❌ Performance issues with lots of articles

### ⚠️ Important - Please Test

#### 4. In-App Web Browsing
**How to test:**
1. Open any article
2. Tap "Read in App" button
3. Try interacting with the web page
4. If you have a site that uses passkeys/security keys, try logging in

**What to look for:**
- ✅ Web page loads correctly
- ✅ Can scroll and interact normally
- ✅ "Done" button dismisses the browser
- ✅ Passkey/security key authentication works (if applicable)
- ❌ Browser fails to load pages
- ❌ Can't dismiss the browser
- ❌ Authentication timeouts

#### 5. Share Button
**How to test:**
1. Open an article
2. Look for share button in top-right
3. Tap it and try sharing to different apps

**What to look for:**
- ✅ Share sheet appears
- ✅ Can share to Messages, Mail, etc.
- ✅ Link and title are correct
- ❌ Share button missing or not working
- ❌ Wrong URL or title being shared

#### 6. External Link Indicators
**How to test:**
1. Browse your article list
2. Look for articles with very short/no descriptions
3. Check if they show an external link icon

**What to look for:**
- ✅ Articles with minimal content show external link icon
- ✅ Tapping them opens in browser or shows "Read in App" option
- ❌ Full articles incorrectly marked as external
- ❌ External articles opening in-app with no content

### 💡 Nice to Test - If You Have Time

#### 7. Feed Management
- Add a new RSS feed
- Remove a feed
- Sync feeds manually (pull to refresh)
- Check for duplicate articles

#### 8. Background Sync
- Leave app in background for an hour
- Check if new articles appear automatically
- Note: iOS controls when background sync happens

#### 9. Dark Mode
- Switch between light/dark mode
- Check if all UI elements look correct
- Look for any hard-to-read text

#### 10. Performance
- Test with many feeds (10+)
- Test with many articles (100+)
- Check scrolling smoothness
- Note any lag or stuttering

## Known Limitations

### iOS Simulator Issues
- Security key authentication doesn't work reliably in simulator
- Test passkey authentication on physical devices only

### Apple Intelligence Requirements
- Only available on iOS 26+ (currently in beta)
- Only available on specific devices (iPhone 15 Pro and newer)
- Requires opt-in to Apple Intelligence in Settings

### WordPress.com/Jetpack
- Some WordPress.com sites may have authentication issues
- This is a known WordPress.com limitation, not an app bug

## How to Report Issues

### Critical Bugs (App Crashes, Data Loss)
**Report immediately via:**
1. TestFlight feedback button
2. Email: whyisjake@gmail.com
3. GitHub Issues: https://github.com/whyisjake/today/issues

**Include:**
- Device model and iOS version
- Exact steps to reproduce
- Screenshots or screen recording
- Console logs if possible

### Minor Issues (UI glitches, typos)
**Report via:**
1. TestFlight feedback
2. Collect a few issues and send one email

### Feature Requests
- Open a GitHub Discussion or Issue
- These will be considered for future versions

## Feedback Questions

Please try to answer these questions in your TestFlight feedback:

### AI Newsletter Generation:
1. Do the generated intros feel natural and engaging?
2. Are titles and subtitles clever and relevant?
3. Does the progressive loading work smoothly?
4. Did you see any inappropriate content or questions asking for help?

### Typography:
1. Do quotes look good (smart/curly instead of straight)?
2. Are there any spacing issues around quotes?
3. Are there any weird characters or boxes?

### Overall Experience:
1. What's your favorite new feature?
2. Is the app faster or slower than v1.1?
3. Any crashes or freezes?
4. Any confusing UI elements?
5. Would you recommend this app to others?

## Version Info

- **Version**: 1.2 (Build 4)
- **Minimum iOS**: 18.0
- **Recommended iOS**: 26.0+ (for Apple Intelligence)
- **Test Duration**: 1-2 weeks
- **Target Release**: After feedback review

## Thank You!

Your testing helps make Today better for everyone. We appreciate you taking the time to explore these new features and report any issues.

Questions? Email whyisjake@gmail.com or open a GitHub issue.

---

Generated: October 27, 2025
