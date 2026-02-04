# Release Checklist for Today RSS Reader

## 🔍 Pre-Release Checklist

### 1. Code Quality & Cleanup

- [ ] **Remove all debug print statements** (or gate them with `#if DEBUG`)
  - Check `SettingsView.swift` (has debug prints on lines 377, 380, 397)
  - Search project-wide for `print(` statements
  
- [ ] **Remove debug-only features from Release builds**
  - ✅ Already gated: Review Testing section in Settings (line 297-314)
  
- [ ] **Fix all compiler warnings**
  - Build in Release mode and fix any warnings
  
- [ ] **Review force unwraps and optionals**
  - Search for `!` and ensure all are safe
  - Check `Link(destination: URL(string:)!)` calls in About section

### 2. App Metadata & Info.plist

- [ ] **Update version number**
  - Set `CFBundleShortVersionString` (Marketing version)
  - Set `CFBundleVersion` (Build number)
  
- [ ] **Add required Privacy descriptions**
  ```xml
  <!-- Add these to Info.plist if needed -->
  <key>NSUserTrackingUsageDescription</key>
  <string>We don't track you, but this is required by Apple</string>
  
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  ```
  
- [ ] **Verify Bundle Identifier**
  - Ensure it matches your developer account
  
- [ ] **Add Copyright notice**
  ```xml
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Jake Spurlock. All rights reserved.</string>
  ```

### 3. App Icon & Assets

- [ ] **Create App Icon in all required sizes**
  - iOS: 1024×1024 App Store icon
  - macOS: Multiple sizes (16pt to 1024pt)
  - Use Asset Catalog for automatic generation
  
- [ ] **Remove unused assets**
  - Clean up any test images or unused resources
  
- [ ] **Ensure all images have proper copyright**
  - Verify you have rights to all images used

### 4. Localization

- [ ] **Review all localized strings**
  - Test with English
  - Ensure all `String(localized:)` calls work
  
- [ ] **Add missing localizations**
  - Check for hardcoded strings that should be localized

### 5. Testing

#### iOS Testing
- [ ] **Test on physical devices**
  - iPhone (compact size class)
  - iPad (regular size class)
  
- [ ] **Test core features**
  - [ ] Add/remove feeds
  - [ ] Sync feeds (manual & background)
  - [ ] Mark articles as read/unread
  - [ ] Favorite articles
  - [ ] Text-to-speech playback
  - [ ] Short article behavior (all 3 modes)
  - [ ] Settings persistence across app restarts
  - [ ] Accent color changes
  - [ ] Appearance mode changes
  
- [ ] **Test edge cases**
  - [ ] App launch with no internet
  - [ ] App launch with no feeds
  - [ ] Very long article titles
  - [ ] Articles with no images
  - [ ] Reddit feed parsing
  
- [ ] **Background testing**
  - [ ] Background fetch works
  - [ ] App doesn't crash when backgrounded

#### macOS Testing
- [ ] **Test all keyboard shortcuts**
  - [ ] ⌘1-4 (navigation)
  - [ ] ⌘R (sync)
  - [ ] ⌘⇧K (mark all read)
  - [ ] J/K (next/prev article)
  - [ ] ⌘F (favorite)
  - [ ] ⌘U (toggle read)
  - [ ] ⌘O (open in browser)
  
- [ ] **Test menu commands**
  - [ ] All Feeds menu items work
  - [ ] Edit menu (Copy, Select All)
  - [ ] View menu (text size - if implemented)
  
- [ ] **Test window management**
  - [ ] Window position/size persists
  - [ ] Minimum window size respected
  - [ ] Settings window opens and functions
  
- [ ] **Run UI Tests**
  ```bash
  # Run in Xcode
  Product → Test (⌘U)
  ```

### 6. Performance & Memory

- [ ] **Profile the app with Instruments**
  - Check for memory leaks
  - Profile time spent in operations
  
- [ ] **Test with large datasets**
  - Add 50+ feeds
  - Sync 1000+ articles
  - Ensure scrolling is smooth
  
- [ ] **Check launch time**
  - Should launch in < 2 seconds
  
- [ ] **Monitor network usage**
  - Ensure efficient feed syncing
  - No unnecessary API calls

### 7. Data & Privacy

- [ ] **Review data collection**
  - Document what data is collected (if any)
  - Ensure GDPR compliance
  
- [ ] **Test data persistence**
  - Articles persist across launches
  - Settings persist across launches
  - No data loss on app termination
  
- [ ] **Export/Import (if applicable)**
  - Can user export their feeds?
  - Can user import OPML?

### 8. App Store Preparation

#### Screenshots
- [ ] **iOS Screenshots** (Required sizes)
  - 6.7" iPhone (iPhone 15 Pro Max)
  - 5.5" iPhone (iPhone 8 Plus) - optional
  - 12.9" iPad Pro
  
- [ ] **macOS Screenshots** (Required)
  - 1280×800 minimum
  - Show main features
  
#### App Store Listing
- [ ] **Write compelling description**
  - Highlight key features
  - Mention "no tracking" if applicable
  
- [ ] **Prepare What's New**
  - List new features for this version
  
- [ ] **Add keywords**
  - RSS, Reader, News, Feeds, etc.
  
- [ ] **Choose categories**
  - Primary: News
  - Secondary: Utilities or Productivity
  
- [ ] **Set age rating**
  - Likely "4+" or "9+" depending on content

### 9. Code Signing & Distribution

- [ ] **Configure Signing**
  - iOS: Development + Distribution certificates
  - macOS: Developer ID Application certificate
  
- [ ] **Enable capabilities**
  - Background fetch (iOS)
  - Network access
  
- [ ] **Create Archive**
  ```
  Product → Archive
  ```
  
- [ ] **Validate Archive**
  - Run validation before submitting
  - Fix any warnings or errors
  
- [ ] **Export for App Store**
  - Upload to App Store Connect

### 10. Final Checks Before Submission

- [ ] **Version numbers match everywhere**
  - Xcode project settings
  - Info.plist
  - App Store Connect
  
- [ ] **All URLs work**
  - Privacy policy URL
  - Support URL
  - Marketing URL
  
- [ ] **Test with clean install**
  - Delete app completely
  - Install fresh build
  - Test first-launch experience
  
- [ ] **Review App Review Guidelines**
  - [Apple's App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  - Ensure compliance

### 11. Post-Submission

- [ ] **Monitor App Store Connect**
  - Watch for review status updates
  
- [ ] **Prepare for questions**
  - Apple may ask for demo video
  - Be ready to explain features
  
- [ ] **Test beta with TestFlight** (optional but recommended)
  - Get feedback from beta testers
  - Fix critical issues before public release

---

## 🚨 Common Rejection Reasons to Avoid

1. **Missing privacy policy** - If you collect any data
2. **Crashes on launch** - Test thoroughly!
3. **Incomplete features** - Don't ship broken features
4. **Poor performance** - Optimize before submitting
5. **Using private APIs** - Stick to public frameworks
6. **Misleading screenshots** - Show actual app features
7. **Copyright violations** - Ensure you own all content

---

## 📋 Quick Command Reference

### Clean Build
```bash
Product → Clean Build Folder (⌘⇧K)
```

### Run Tests
```bash
Product → Test (⌘U)
```

### Archive
```bash
Product → Archive
```

### Check for TODO/FIXME
```bash
grep -r "TODO\|FIXME" --include="*.swift" .
```

### Find Debug Prints
```bash
grep -r "print(" --include="*.swift" . | grep -v "//.*print("
```

---

## ✅ When Everything is Done

**Congratulations!** You're ready to submit to the App Store! 🎉

**Final Steps:**
1. Create Archive in Xcode
2. Validate Archive
3. Upload to App Store Connect
4. Fill out App Store metadata
5. Submit for Review
6. Wait 1-3 days for review

**Pro Tip:** Submit on Tuesday-Thursday for fastest review times. Avoid weekends and holidays.

---

*Good luck with your release! 🚀*
