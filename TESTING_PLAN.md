# Testing Plan - Next Release (v1.3.0)

**Current Version:** v1.2.1 (Build 5)
**Target Version:** v1.3.0
**Date:** 2025-10-30

---

## 🎯 Release Scope

### New Features (Pending Merge)
- [ ] Feed navigation improvements (tap feed → articles view)
- [ ] AI message fade-in animations
- [ ] Reddit RSS feed support with subreddit badges
- [ ] AI topic-based search ("give me tech stories")
- [ ] Keyboard dismiss after sending AI message
- [ ] Loading progress bars (replacing centered spinners)
- [ ] Toggle for opening short articles directly in browser

### Bug Fixes
- [ ] Any critical issues from TestFlight feedback
- [ ] Performance improvements for large feed lists

---

## ✅ Core Functionality Regression Testing

### RSS Feed Management
- [ ] **Add Feed**
  - [ ] Add valid RSS feed URL
  - [ ] Add valid Atom feed URL
  - [ ] Add invalid URL (should show error)
  - [ ] Add duplicate feed (should detect)
  - [ ] Add Reddit RSS feed (e.g., https://www.reddit.com/r/baseball.rss)
  - [ ] Test all category options (general, work, social, tech, news, politics)
  - [ ] Test custom category name

- [ ] **Edit Feed**
  - [ ] Change feed title
  - [ ] Change feed URL
  - [ ] Change feed category
  - [ ] Save changes and verify persistence

- [ ] **Delete Feed**
  - [ ] Delete feed via swipe action
  - [ ] Delete feed via context menu
  - [ ] Verify articles are cascade-deleted
  - [ ] Verify UI updates correctly

- [ ] **Feed Sync**
  - [ ] Pull-to-refresh on feed list
  - [ ] Manual "Sync All Feeds" from menu
  - [ ] Verify progress indicator shows
  - [ ] Verify new articles appear
  - [ ] Verify duplicate articles not created

- [ ] **OPML Import/Export**
  - [ ] Export feeds to clipboard
  - [ ] Import valid OPML file
  - [ ] Import OPML with categories
  - [ ] Import OPML with invalid feeds (should skip)
  - [ ] Verify imported feeds sync correctly

### Article Reading
- [ ] **Article List (Today View)**
  - [ ] View today's articles
  - [ ] Load more days (scroll down)
  - [ ] Filter by category
  - [ ] Search articles by keyword
  - [ ] Toggle show/hide read articles
  - [ ] Verify unread count badge accuracy
  - [ ] Check article images load correctly
  - [ ] Verify time-ago formatting ("2h ago", "1 day ago")

- [ ] **NEW: Feed Articles View**
  - [ ] Tap feed in feed list → opens feed articles view
  - [ ] Verify shows only articles from that feed
  - [ ] Verify "unread only" filter works
  - [ ] Toggle "Show Read" articles
  - [ ] Mark all as read button
  - [ ] Swipe article to mark read/unread
  - [ ] Navigation back to feed list works

- [ ] **Article Detail**
  - [ ] Open article with full content → shows reader view
  - [ ] Open article with minimal content → opens Safari View
  - [ ] Verify texturize applies (curly quotes, em dashes)
  - [ ] Font selection (serif vs sans-serif) applies
  - [ ] Share article via share sheet
  - [ ] Mark as read/unread via toolbar
  - [ ] Add/remove favorite via toolbar
  - [ ] Open in Safari via toolbar
  - [ ] Previous/Next navigation works
  - [ ] Back navigation preserves scroll position

- [ ] **NEW: Reddit Article Features**
  - [ ] Reddit posts show orange "r/subreddit" badge
  - [ ] Comments button appears in toolbar for Reddit posts
  - [ ] Tapping Comments opens Reddit discussion page
  - [ ] Reddit comments load in Safari View
  - [ ] Navigation between article and comments works

- [ ] **Article Metadata**
  - [ ] Published date displays correctly
  - [ ] Feed title displays correctly
  - [ ] Author name displays (when available)
  - [ ] Read status indicator works
  - [ ] Favorite star displays correctly
  - [ ] External link indicator shows for minimal content

### AI Features

- [ ] **AI Summary (Tab)**
  - [ ] Generate summary from unread articles
  - [ ] Summary includes article count
  - [ ] Summary shows by category
  - [ ] Summary shows most active sources
  - [ ] Summary shows trending keywords
  - [ ] Tap article in summary list → opens detail
  - [ ] Summary updates when articles marked as read
  - [ ] Apple Intelligence used on iOS 26+ (check console logs)
  - [ ] Fallback to NaturalLanguage on iOS 18-25

- [ ] **AI Chat**
  - [ ] Send message → AI responds
  - [ ] NEW: AI messages fade in smoothly (1 second)
  - [ ] User messages appear instantly
  - [ ] Typing indicator shows while generating
  - [ ] NEW: Keyboard dismisses after sending message
  - [ ] Conversation history persists in session
  - [ ] Markdown formatting renders correctly
  - [ ] Code blocks format properly
  - [ ] Links in responses are tappable

- [ ] **AI Chat - Query Types**
  - [ ] "How many articles?" → shows count
  - [ ] "Summarize today's articles" → generates summary
  - [ ] "What should I read?" → suggests articles
  - [ ] "Show me unread" → lists unread articles
  - [ ] "What's trending?" → shows keywords
  - [ ] NEW: "Give me some tech stories" → filters tech articles
  - [ ] NEW: "Show me news articles" → filters news
  - [ ] NEW: "Any social media posts?" → filters social
  - [ ] "Find articles about X" → searches content
  - [ ] "Help" → shows available commands

- [ ] **Newsletter Generation**
  - [ ] Generate newsletter from recent articles
  - [ ] Header with creative title/subtitle generates
  - [ ] Articles grouped by category
  - [ ] Witty intros generate (or use fallbacks)
  - [ ] Tap article in newsletter → opens detail
  - [ ] Newsletter items display in chat format
  - [ ] "Mark all as read" works from newsletter
  - [ ] Context window errors handled gracefully (known issue)

### Background Sync
- [ ] **Background Refresh**
  - [ ] App registers for background refresh on launch
  - [ ] Background sync runs (check Settings → General → Background App Refresh)
  - [ ] New articles appear after background sync
  - [ ] Background sync respects iOS power management
  - [ ] Test: Force background refresh via Xcode (Debug → Simulate Background Fetch)

### Settings & Preferences
- [ ] **Appearance**
  - [ ] Dark mode toggle works
  - [ ] System theme auto-switches
  - [ ] Accent color selection applies throughout app
  - [ ] Font preference (serif/sans-serif) applies to articles

- [ ] **Data Management**
  - [ ] Clear all data removes feeds and articles
  - [ ] App state resets to onboarding
  - [ ] Confirm button prevents accidental deletion

- [ ] **About**
  - [ ] Version number displays correctly
  - [ ] Build number displays correctly
  - [ ] Privacy policy loads (if added)

---

## 🔄 State Management Testing

### Data Persistence
- [ ] Add feeds → kill app → relaunch → feeds persist
- [ ] Mark articles read → kill app → relaunch → read status persists
- [ ] Change settings → kill app → relaunch → settings persist
- [ ] Favorite articles → kill app → relaunch → favorites persist
- [ ] AI chat history → background app → return → history persists (within session)

### Sync & Refresh
- [ ] Pull-to-refresh updates article list immediately
- [ ] Background sync adds new articles without user action
- [ ] Syncing one feed doesn't affect other feeds
- [ ] Failed feed sync doesn't crash app
- [ ] Network errors show appropriate messages

---

## 📱 Platform & Device Testing

### iOS Versions
- [ ] **iOS 18.0** - Minimum supported version
  - [ ] All core features work
  - [ ] Apple Intelligence features show "not available" gracefully
  - [ ] Fallback AI methods work
- [ ] **iOS 26.0+** - Apple Intelligence available
  - [ ] Apple Intelligence initializes correctly
  - [ ] Newsletter generation uses SystemLanguageModel
  - [ ] AI chat uses on-device model
  - [ ] Check console for "🧠 AIService: isAvailable = true"

### Device Types
- [ ] **iPhone (various sizes)**
  - [ ] iPhone SE (small screen)
  - [ ] iPhone 17 (standard)
  - [ ] iPhone 17 Pro Max (large screen)
  - [ ] Verify layout adapts to screen size
  - [ ] Verify text is readable on all sizes

- [ ] **iPad**
  - [ ] App runs in compatibility mode
  - [ ] Layout is usable (not optimized yet - known limitation)
  - [ ] All features work on iPad

### Orientations
- [ ] **Portrait** - Primary orientation
- [ ] **Landscape** - Should work but may not be optimized

---

## 🚨 Edge Cases & Error Scenarios

### Network Conditions
- [ ] No internet connection
  - [ ] Shows appropriate error message
  - [ ] Cached content still readable
  - [ ] Sync fails gracefully
- [ ] Slow/intermittent connection
  - [ ] Loading indicators show
  - [ ] Timeouts handled gracefully
  - [ ] Partial content doesn't corrupt data
- [ ] Feed returns 404/500 error
  - [ ] Error message shows
  - [ ] Other feeds continue to work
  - [ ] Feed can be removed or updated

### Content Edge Cases
- [ ] **RSS Feed Variations**
  - [ ] Feed with no articles
  - [ ] Feed with very long titles (>200 chars)
  - [ ] Feed with HTML entities in title
  - [ ] Feed with special characters (emoji, unicode)
  - [ ] Feed with malformed XML (should handle gracefully)
  - [ ] Feed with missing required fields

- [ ] **Article Content**
  - [ ] Article with no description
  - [ ] Article with no published date
  - [ ] Article with no author
  - [ ] Article with very long content
  - [ ] Article with embedded images
  - [ ] Article with video embeds (may not display)
  - [ ] Article with HTML tables/complex formatting

- [ ] **Search & Filtering**
  - [ ] Search with no results
  - [ ] Search with special characters
  - [ ] Filter by category with no articles
  - [ ] Empty AI chat queries
  - [ ] AI chat with very long prompts

### Data Limits
- [ ] 100+ feeds
- [ ] 1000+ articles
- [ ] Large article content (>50KB)
- [ ] Rapid sync operations (spam pull-to-refresh)
- [ ] Multiple simultaneous feed syncs

---

## 🎨 UI/UX Testing

### Visual Design
- [ ] Consistent spacing and padding
- [ ] Colors match design system
- [ ] Icons render correctly at all sizes
- [ ] SF Symbols display properly
- [ ] Accent color applies consistently
- [ ] Dark mode colors are readable
- [ ] Light mode colors are readable

### Animations & Transitions
- [ ] NEW: AI message fade-in is smooth (1 second)
- [ ] NEW: Loading progress bars animate correctly
- [ ] Pull-to-refresh animation smooth
- [ ] Sheet presentations slide smoothly
- [ ] Navigation transitions are fluid
- [ ] No jarring layout shifts

### Typography
- [ ] Headlines readable and properly sized
- [ ] Body text readable
- [ ] Curly quotes render correctly
- [ ] Em dashes (—) render correctly
- [ ] En dashes (–) render correctly
- [ ] Font size appropriate for content type
- [ ] Serif/sans-serif toggle applies correctly

---

## ⚡ Performance Testing

### Launch Performance
- [ ] Cold launch time < 3 seconds
- [ ] Warm launch time < 1 second
- [ ] Memory usage reasonable (< 100MB typical)
- [ ] No lag on launch

### Scroll Performance
- [ ] Article list scrolls smoothly with 100+ articles
- [ ] Images load without stuttering
- [ ] LazyVStack efficiently loads cells
- [ ] No memory leaks during extended scrolling

### Network Performance
- [ ] Multiple feed sync completes in reasonable time
- [ ] Large feeds (100+ articles) parse efficiently
- [ ] Image loading doesn't block UI
- [ ] Background sync doesn't drain battery excessively

### AI Performance
- [ ] Newsletter generation completes in < 10 seconds (iOS 26+)
- [ ] Chat responses arrive in < 5 seconds
- [ ] AI processing doesn't freeze UI
- [ ] Typing indicator shows while processing

---

## ♿ Accessibility Testing

### VoiceOver
- [ ] All buttons have labels
- [ ] Article titles are announced
- [ ] Navigation is logical with VoiceOver
- [ ] Form fields are labeled correctly
- [ ] Alerts and errors are announced

### Dynamic Type
- [ ] Text scales with system font size
- [ ] Layout doesn't break at largest text size
- [ ] All text remains readable

### Color Contrast
- [ ] Text meets WCAG AA standards
- [ ] Buttons are distinguishable
- [ ] Status indicators are clear

---

## 🔒 Privacy & Security

### Data Storage
- [ ] All data stored locally (no cloud)
- [ ] No analytics or tracking
- [ ] No third-party SDKs
- [ ] Feed credentials not exposed (if any)

### Network Security
- [ ] HTTPS enforced for feed URLs (or warn)
- [ ] No sensitive data in logs
- [ ] User-Agent string appropriate

---

## 📝 Known Issues (Document, Don't Block)

### Issues to Document
- [ ] Context window overflow in newsletter generation (occasional)
- [ ] iPad layout not optimized (compatibility mode only)
- [ ] Background sync timing controlled by iOS (not guaranteed)

---

## ✈️ TestFlight Beta Testing

### Beta Test Checklist
- [ ] Distribute build to internal testers
- [ ] Collect feedback on new features
- [ ] Monitor crash reports
- [ ] Review analytics (if any)
- [ ] Address critical bugs before App Store submission

### Feedback Collection
- [ ] Feed navigation usability
- [ ] AI message animation feel (too fast/slow?)
- [ ] Reddit feed features useful?
- [ ] Topic search accuracy
- [ ] Any unexpected behaviors

---

## 📋 Pre-Release Checklist

### Code Quality
- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Code formatted consistently
- [ ] TODOs addressed or documented

### Documentation
- [ ] README updated with new features
- [ ] CHANGELOG.md updated
- [ ] Version history in README updated
- [ ] Known issues documented

### Build Verification
- [ ] Version number incremented
- [ ] Build number incremented
- [ ] Release notes prepared
- [ ] Screenshots updated (if UI changed)
- [ ] App Store metadata updated

### Final Checks
- [ ] Test on physical device (not just simulator)
- [ ] Test with fresh install (not upgrade)
- [ ] Test with no network
- [ ] Test with many feeds/articles
- [ ] All critical paths work

---

## 🚀 Release Criteria

### Must Have (Blocking)
- [ ] No crashes in core flows
- [ ] Feed sync works reliably
- [ ] Articles display correctly
- [ ] AI features work (or degrade gracefully)
- [ ] Data persists correctly

### Should Have (Important)
- [ ] Performance is acceptable
- [ ] UI is polished
- [ ] Error messages are helpful
- [ ] New features work as designed

### Nice to Have (Non-Blocking)
- [ ] All edge cases handled
- [ ] Perfect accessibility support
- [ ] Zero compiler warnings
- [ ] 100% test coverage

---

## 📞 Contacts & Resources

- **GitHub Issues:** https://github.com/whyisjake/today/issues
- **TestFlight:** [Link when available]
- **App Store:** https://apps.apple.com/us/app/today-rss-reader/id6754362337
- **Feedback:** [Your contact method]

---

**Notes:**
- Mark items with ✅ when tested and passing
- Mark items with ❌ when tested and failing (add issue number)
- Mark items with ⚠️ when partially working (add notes)
- Add comments for any unexpected behaviors
