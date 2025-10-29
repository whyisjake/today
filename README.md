# Today

A modern, privacy-focused RSS reader for iOS with AI-powered content summarization.

![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Core Functionality
- 📰 **RSS Feed Management** - Subscribe to your favorite RSS feeds with OPML import/export support
- 🤖 **AI-Powered Summaries** - Intelligent article summarization using Apple Intelligence (iOS 26+) with graceful fallback to NaturalLanguage framework
- 🔄 **Background Sync** - Automatic feed updates with hourly background refresh
- 📅 **Day-Based Navigation** - Browse articles by Today, Yesterday, and older with infinite scroll
- 🔍 **Smart Filtering** - Filter by category, search articles, and mark as read/unread
- ⭐ **Favorites** - Save important articles for later
- 🎨 **Typography** - WordPress-style smart quotes and em/en dashes for beautiful text rendering

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
xcrun agvtool new-marketing-version 1.3

# Increment build number
xcrun agvtool next-version -all
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
