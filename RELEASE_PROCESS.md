# Release Process

This document outlines the process for creating and submitting new releases of the Today RSS Reader app.

## Pre-Release Checklist

Before starting a release, ensure:

- [ ] All features are tested and working
- [ ] No critical bugs in the current build
- [ ] Code is committed and pushed to main branch
- [ ] All tests pass (if applicable)
- [ ] Performance is acceptable on target devices

## Version Numbering

The app uses semantic versioning with the format: `MAJOR.MINOR (BUILD)`

- **MAJOR**: Significant changes, major new features, breaking changes (e.g., 2.0)
- **MINOR**: New features, enhancements, non-breaking changes (e.g., 1.1, 1.2)
- **BUILD**: Incremental build number for each submission (e.g., 1, 2, 3)

Examples:
- `1.0 (1)` - Initial release
- `1.1 (2)` - First update with new features
- `1.2 (3)` - Second update with enhancements

## Release Steps

### 1. Update Version Numbers

From the project root directory:

```bash
# Update marketing version (e.g., 1.2)
xcrun agvtool new-marketing-version 1.2

# Increment build number
xcrun agvtool next-version -all

# Manually verify the project file was updated
plutil -p Today.xcodeproj/project.pbxproj | grep "MARKETING_VERSION"
```

**Important**: If `MARKETING_VERSION` wasn't updated in the project file, manually update it:

```bash
sed -i '' 's/MARKETING_VERSION = 1.1/MARKETING_VERSION = 1.2/g' Today.xcodeproj/project.pbxproj
```

### 2. Commit Version Bump

Create a commit with release notes:

```bash
git add -A
git commit -m "Bump version to 1.2 (build 3)

Version 1.2 Release - [Brief Title]

New Features:
- Feature 1 description
- Feature 2 description

Improvements:
- Improvement 1
- Improvement 2

Bug Fixes:
- Fix description

Technical:
- Technical changes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 3. Create Git Tag

Tag the release with detailed notes:

```bash
git tag -a v1.2 -m "Release v1.2 - [Brief Title]

Major Features:
- 🎉 Feature 1
  - Details

- 🚀 Feature 2
  - Details

Improvements:
- Improvement 1
- Improvement 2

Bug Fixes:
- Fix description

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Verify the tag:

```bash
git tag -l -n9 v1.2
```

### 4. Push to Remote

```bash
# Push commits
git push origin main

# Push tags
git push origin v1.2
```

### 5. Build for App Store

1. **Open Xcode**
   ```bash
   open Today.xcodeproj
   ```

2. **Select Target**
   - Select "Any iOS Device (arm64)" or a connected device
   - DO NOT select a simulator

3. **Clean Build Folder**
   - Menu: Product > Clean Build Folder
   - Or: `Cmd+Shift+K`

4. **Archive the Build**
   - Menu: Product > Archive
   - Or: `Cmd+Shift+B` (if configured)
   - Wait for archive to complete

5. **Verify Version**
   - In the Organizer window, verify the version shows correctly
   - Should display: `1.2 (3)` (or your version numbers)
   - If incorrect, go back to Step 1 and fix version numbers

### 6. Distribute to App Store

1. **Open Organizer**
   - Window > Organizer (or `Cmd+Shift+Option+O`)
   - Select the "Archives" tab

2. **Validate App**
   - Select your archive
   - Click "Validate App"
   - Choose distribution method: "App Store Connect"
   - Wait for validation to complete
   - Fix any errors or warnings

3. **Distribute App**
   - Click "Distribute App"
   - Choose: "App Store Connect"
   - Select distribution options:
     - Upload symbols: ✅ Yes (recommended)
     - Manage Version and Build: Let Xcode handle it
   - Click "Upload"
   - Wait for upload to complete

### 7. Submit for Review in App Store Connect

1. **Go to App Store Connect**
   - Visit: https://appstoreconnect.apple.com
   - Select your app

2. **Create New Version** (if needed)
   - Click "+ Version or Platform"
   - Enter version number (e.g., 1.2)

3. **Add What's New**
   - Enter release notes for users (keep it brief and user-friendly)
   - Example:
     ```
     What's New in 1.2:

     • Smart AI summaries powered by Apple Intelligence
     • Browse articles by day: Today, Yesterday, and older
     • Improved reading experience with quick actions
     • Better article selection prioritizing recent and unread content

     We're constantly improving Today. Thanks for your feedback!
     ```

4. **Select Build**
   - In the "Build" section, click the (+) icon
   - Select the build you just uploaded
   - Wait for it to finish processing (can take 10-30 minutes)

5. **Review App Information**
   - Verify screenshots are current
   - Check app description
   - Verify keywords and categories

6. **Submit for Review**
   - Click "Submit for Review"
   - Answer any additional questions
   - Confirm submission

## Post-Submission

### Monitor Review Status

Check App Store Connect regularly:
- **Waiting for Review**: In queue (can take 1-7 days for first submission, 24-48 hours for updates)
- **In Review**: Apple is actively reviewing (usually takes a few hours)
- **Pending Developer Release**: Approved! You can release manually or auto-release
- **Ready for Sale**: Live on the App Store

### If Rejected

1. Read the rejection reason carefully
2. Fix the issues
3. Increment build number: `xcrun agvtool next-version -all`
4. Create a new archive
5. Upload the new build
6. Update version info in App Store Connect
7. Respond to the rejection with what you fixed
8. Resubmit for review

## Release Timeline Expectations

### First Submission (v1.0 or v1.1)
- **Validation**: A few minutes
- **Processing**: 10-30 minutes after upload
- **Review Queue**: 3-7 days (sometimes longer)
- **In Review**: 2-24 hours
- **Total**: Typically 4-8 days

### Subsequent Updates (v1.2+)
- **Validation**: A few minutes
- **Processing**: 10-30 minutes
- **Review Queue**: 24-48 hours (much faster!)
- **In Review**: 2-12 hours
- **Total**: Typically 1-3 days

## Tips & Best Practices

### Version Management
- ✅ Always test on a real device before archiving
- ✅ Keep build numbers incrementing (never reuse)
- ✅ Use meaningful version numbers (1.1, 1.2, etc.)
- ✅ Document what's new in each version
- ❌ Don't skip version numbers unnecessarily

### App Store Optimization
- ✅ Write clear, user-friendly release notes
- ✅ Update screenshots when UI changes significantly
- ✅ Respond to user reviews (shows you're engaged)
- ✅ Monitor crash reports and fix issues quickly

### Timing Releases
- ✅ Submit updates during weekdays for faster review
- ✅ Avoid major holidays (reviews are slower)
- ✅ Consider user time zones for release timing
- ❌ Don't rush releases - quality over speed

### Emergency Fixes
If you discover a critical bug after submission:
- **Before approval**: Delete the build and submit a new one
- **After approval but not released**: Pull the release and fix
- **After release**: Submit an emergency update ASAP with incremented build number

## Troubleshooting

### Version Not Updating in Archive
**Problem**: Archive shows old version (e.g., 1.1 instead of 1.2)

**Solution**:
```bash
# Manually update project file
sed -i '' 's/MARKETING_VERSION = 1.1/MARKETING_VERSION = 1.2/g' Today.xcodeproj/project.pbxproj

# Commit the change
git add Today.xcodeproj/project.pbxproj
git commit --amend --no-edit

# Update the tag
git tag -d v1.2
git tag -a v1.2 -m "Release notes here"
```

### Archive Upload Fails
**Common causes**:
- Invalid provisioning profile
- Missing signing certificate
- Invalid bundle identifier
- Missing required capabilities

**Solution**: Check the error message and fix the specific issue in project settings

### Build Processing Takes Forever
**What to do**:
- Be patient (can take up to an hour)
- If stuck for >2 hours, contact Apple Developer Support
- Try uploading again if it fails

## Reference

### Useful Commands

```bash
# Check current versions
agvtool what-version                    # Build number
agvtool what-marketing-version          # Marketing version

# View recent commits
git log --oneline -10

# View tags
git tag -l

# View tag details
git tag -l -n9 v1.2

# View uncommitted changes
git status
git diff
```

### App Store Connect Links
- **App Store Connect**: https://appstoreconnect.apple.com
- **Developer Portal**: https://developer.apple.com/account
- **TestFlight**: https://appstoreconnect.apple.com/apps/[app-id]/testflight

### Support Resources
- **App Store Review Guidelines**: https://developer.apple.com/app-store/review/guidelines/
- **Human Interface Guidelines**: https://developer.apple.com/design/human-interface-guidelines/
- **Technical Support**: https://developer.apple.com/support/

---

**Last Updated**: October 25, 2025
**Document Version**: 1.0
