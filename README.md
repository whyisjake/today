# Today

A modern, privacy-focused RSS reader for iOS with AI-powered content summarization.

![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Core Functionality
- 📰 **RSS Feed Management** - Subscribe to your favorite RSS feeds with OPML import/export support
- 🤖 **AI-Powered Summaries** - Intelligent article summarization using Apple Intelligence (iOS 26+) with graceful fallback to NaturalLanguage framework
- 🎙️ **Text-to-Speech Audio Player** - Listen to articles with full playback controls, variable speed (0.5x-2x), and background playback support
- 🗣️ **Voice Selection** - Choose from high-quality voices in your language with preview functionality
- 🔒 **Lock Screen Integration** - Rich Now Playing controls with article thumbnails and accurate duration estimates
- 🔄 **Background Sync** - Automatic feed updates with hourly background refresh
- 📅 **Day-Based Navigation** - Browse articles by Today, Yesterday, and older with infinite scroll
- 🔍 **Smart Filtering** - Filter by category, search articles, and mark as read/unread
- ⭐ **Favorites** - Save important articles for later
- 🎨 **Typography** - WordPress-style smart quotes and em/en dashes for beautiful text rendering
- 🔴 **Reddit RSS Support** - Native Reddit integration with JSON API, animated GIF/video playback, gallery images with zoom/pan, comments view, and author display
- 🌐 **Multi-Language Support** - Full app localization in English, German, Spanish, and Japanese

### User Experience
- 🌓 **Dark Mode Support** - Automatic light/dark theme with manual override
- 🎨 **Customizable Accent Colors** - Choose from 6 vibrant color options
- 📖 **Font Options** - Select between serif (New York/Georgia) and sans-serif (SF Pro)
- 📱 **Pull to Refresh** - Quickly sync your feeds
- 🔗 **Flexible Reading** - Read in-app with Safari View Controller or open in external browser
- 📤 **Easy Sharing** - Share articles via iOS share sheet

### Privacy & Data
- 🔒 **Privacy-First** - All data stored locally with SwiftData
- 📱 **No Account Required** - No sign-up, no tracking, no cloud sync
- 💾 **OPML Support** - Import/export your feed subscriptions
- 🗑️ **Data Portability** - Export your data anytime

## Screenshots

<!-- Add screenshots here when ready -->

## Requirements

- iOS 18.0 or later
- iPhone or iPad
- Xcode 16.0+ (for development)

## Installation

### From App Store

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/us/app/today-rss-reader/id6754362337)

Today is available for free on the App Store for iOS 18.0 and later.

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/jakespurlock/today.git
cd today/Today
```

2. Open the project in Xcode:
```bash
open Today.xcodeproj
```

3. Select your development team in the project settings under "Signing & Capabilities"

4. Build and run (⌘R)

## Architecture

Today is built using modern iOS development practices:

- **SwiftUI** - Declarative UI framework
- **SwiftData** - Persistence layer for feeds and articles
- **Swift Concurrency** - Async/await for networking and background tasks
- **Apple Intelligence** - On-device LLM for article summaries (iOS 26+)
- **Background Tasks** - BGAppRefreshTask for automatic feed syncing
- **Safari View Controller** - In-app web browsing

### Project Structure

```
Today/
├── Models/           # SwiftData models (Feed, Article)
├── Views/            # SwiftUI views
├── Services/         # Business logic (RSS parsing, AI, background sync)
├── Utilities/        # Helper utilities (Texturizer)
└── Resources/        # Assets and configuration
```

For detailed architecture documentation, see [CLAUDE.md](CLAUDE.md).

## Development

### Running Tests

```bash
# Run all tests
xcodebuild test -project Today.xcodeproj -scheme Today \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test suite
xcodebuild test -project Today.xcodeproj -scheme Today \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TodayTests/TexturizerTests
```

### Building

```bash
# Debug build
xcodebuild -project Today.xcodeproj -scheme Today \
  -configuration Debug build

# Release build
xcodebuild -project Today.xcodeproj -scheme Today \
  -configuration Release build
```

### Release Process

For detailed release instructions, see [RELEASE_PROCESS.md](RELEASE_PROCESS.md).

Quick version bump:
```bash
# Update marketing version
xcrun agvtool new-marketing-version 1.4.0

# Increment build number
xcrun agvtool next-version -all

# Note: agvtool may only update Info.plist
# Verify and update project.pbxproj manually if needed:
grep "MARKETING_VERSION = " Today.xcodeproj/project.pbxproj
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Guidelines

1. Follow Swift API Design Guidelines
2. Write tests for new features
3. Update documentation for significant changes
4. Ensure all tests pass before submitting PR
5. Use meaningful commit messages

### Code of Conduct

Be respectful, inclusive, and constructive in all interactions.

## License

This project uses a dual-license structure:

### Main Application - MIT License

The majority of this project is licensed under the **MIT License**.

Copyright (c) 2025 Jake Spurlock

See [LICENSE](LICENSE) for full details.

### Texturizer Component - GPL v2+

The file `Today/Utilities/Texturizer.swift` is licensed under the **GNU General Public License v2 or later**, as it is derived from WordPress's `wptexturize()` function.

This component is clearly marked with GPL licensing in its header comments and is isolated from the rest of the application to maintain license clarity.

### Why Dual License?

The Texturizer component is a port of WordPress's text beautification functionality, which is GPL-licensed. To respect WordPress's license while keeping the rest of the app under MIT, we use this dual-license structure.

## Credits

### Author
**Jake Spurlock**
- Website: [jakespurlock.com](https://jakespurlock.com)
- GitHub: [@jakespurlock](https://github.com/jakespurlock)
- Twitter: [@whyisjake](https://twitter.com/whyisjake)

### Acknowledgments

- **WordPress** - Texturizer is derived from the `wptexturize()` function in WordPress core
- **Apple** - SwiftUI, SwiftData, and Apple Intelligence frameworks
- **RSS Community** - For keeping web syndication alive

## Roadmap

### Planned Features
- [ ] iPad-optimized layout with sidebar navigation
- [ ] Article content extraction (reader mode)
- [ ] Podcast support
- [ ] iCloud sync (optional)
- [ ] Home Screen widgets
- [ ] Siri shortcuts
- [ ] Feed discovery from websites

### Under Consideration
- macOS companion app
- Watch app for reading queue
- Custom notification rules
- Article annotations and highlights

## Support

### Issues and Bug Reports
Please report issues on [GitHub Issues](https://github.com/jakespurlock/today/issues).

### Feature Requests
Open a discussion or create a feature request issue.

### Documentation
- [CLAUDE.md](CLAUDE.md) - Project overview and architecture
- [RELEASE_PROCESS.md](RELEASE_PROCESS.md) - Release and deployment guide
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Detailed feature documentation

## Privacy Policy

Today respects your privacy:
- ✅ All data stored locally on your device
- ✅ No analytics or tracking
- ✅ No ads
- ✅ No account creation required
- ✅ No data sent to external servers (except when fetching RSS feeds)
- ✅ AI processing happens on-device (when using Apple Intelligence)

## Version History

### v1.8.0 (Build 12) - November 2025
**Reddit Improvements & Content Filtering**
- 🔴 **Consolidated Reddit Views** - Unified post and comment viewing for streamlined experience
- 🤖 **AutoModerator Filtering** - Automatically hide AutoModerator and deleted comments
- 📺 **Fullscreen Video Playback** - Reddit embedded videos now support fullscreen mode
- 🔤 **HTML Entity Decoding** - Proper display of special characters (&, <, >, etc.) in all content
- 🎯 **Discrete Content Filtering** - New system for filtering unwanted content
- 🐛 **Bug Fixes**:
  - Fixed HTML entities (`&amp;`, `&lt;`, etc.) displaying in article titles
  - Fixed Reddit posts in AI summaries opening in wrong view
  - Fixed video/GIF playback interrupting background audio
- 🛠️ **Code Quality** - Removed 381 lines of duplicate code for better maintainability

### v1.7.0 (Build 11) - November 2025
**Brand Refresh**
- 🎨 **New App Icon** - Fresh, modern icon with International Orange branding
- 📱 **Simplified App Name** - Clean "Today" display name on home screen
- ✨ **Polish & Refinement** - Enhanced visual identity and user experience

### v1.6.0 (Build 10) - November 20, 2025
**Text-to-Speech Audio Player & Voice Enhancements**
- 🎙️ **Text-to-Speech Audio Player** - Listen to articles with full-featured audio playback
- ⏯️ **Playback Controls** - Play, pause, stop, and seek through articles with progress slider
- 🎚️ **Variable Speed** - Adjustable playback speed from 0.5x to 2x
- 📱 **Mini Player** - Persistent audio controls across all tabs
- 🔇 **Background Playback** - Continue listening with screen off
- 🔒 **Lock Screen Controls** - Full Now Playing integration with article thumbnails
- 🗣️ **Voice Selection** - Choose from high-quality voices with live preview
- 🌐 **Smart Filtering** - Only shows voices for your device language
- 🎯 **Voice Quality** - Enhanced and Premium voice indicators
- 🖼️ **Article Artwork** - Shows article thumbnails on lock screen with intelligent caching
- ⏱️ **Accurate Duration** - Real-time estimates based on word count
- 🌍 **Complete Localization** - All audio features translated to German, Spanish, and Japanese
- 🔄 **Background Sync Improvements** - More reliable feed updates with persistent tracking
- ⭐ **App Store Review System** - Respectful review prompts based on usage

### v1.5.0 - November 2025
**Multi-Language Support**
- 🌐 **Complete Spanish localization** - Full app translation including AI features
- 🌐 **Complete German localization** - Full app translation including AI features
- 🌐 **Complete Japanese localization** - Full app translation including AI features
- 🎨 **Localized Settings** - Theme and Font options translated
- 🗣️ **Community Credit** - Special thanks to u/kikher for the multi-language suggestion

### v1.4.0 (Build 7) - November 15, 2025
**Reddit RSS Support**
- 🔴 **Native Reddit integration** - Add subreddits as feeds using simple names (e.g., "technology")
- 🎬 **Animated GIF/video playback** - Reddit posts with animated content play automatically
- 🖼️ **Gallery support** - Swipe through multi-image posts with pinch-to-zoom and pan gestures
- 💬 **Comments view** - Read Reddit comments directly in the app with proper threading
- 👤 **Author display** - See post authors in list view instead of feed names
- 📰 **Newsletter integration** - Reddit posts work seamlessly in AI-generated newsletters
- 🎯 **Simplified feed picker** - Choose between RSS Feed or Reddit when adding new feeds
- 🔄 **Previous/Next navigation** - Navigate between Reddit posts and articles

### v1.3.0 (Build 6) - November 1, 2025
**Feed Navigation & Category Improvements**
- 🎯 **Tap feed to view articles** - New feed article view with unread filtering
- 📊 **Unread count badges** on feed list items
- 🔄 **Swipe/long-press for settings** - Access edit/delete via swipe or context menu
- 📂 **Smart category filters** - Hide empty categories, show only categories with articles
- 🔤 **Title-case categories** - Consistent capitalization (General, Work, Tech, etc.)
- 🔄 **One-time migration** - Automatically updates existing feeds to title-case
- 🎨 **Preserved custom categories** - Your custom category names stay exactly as set
- 🐛 **Bug fix:** Category capitalization inconsistencies (thanks @desrosj)

### v1.2.1 (Build 5) - October 28, 2025 🎉
**Official App Store Launch**
- 🚀 Public release on App Store
- 🔧 Fixed iOS deployment target (18.0+ for wide compatibility)
- 🤖 Apple Intelligence properly available on iOS 26+ devices
- 🐛 Resolved availability checks for stored properties
- 📢 Marketing launch across social platforms

### v1.2 (Build 3) - October 2025
- 🎉 Apple Intelligence integration for smart summaries
- 📅 Day-based article navigation (Today/Yesterday/Older)
- 📖 Improved article detail toolbar with context menu
- 📤 Share button in article detail
- 🎨 Dynamic version display in Settings
- ✨ Smart quotes and typography improvements
- 🐛 Bug fixes and performance improvements

### v1.1 (Build 2) - October 2025
- 🎨 Serif/sans-serif font preference
- 🎨 Customizable accent colors
- 🐛 Initial bug fixes

### v1.0 (Build 1) - October 2025
- 🎉 Initial release
- 📰 RSS feed management
- 🤖 AI summaries (NaturalLanguage)
- 🔄 Background sync
- 🌓 Dark mode support
- 📱 OPML import/export

---

Made with ♥️ in California
