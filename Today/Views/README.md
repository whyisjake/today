# Today - Modern RSS Reader

A beautiful, native RSS reader for iOS and macOS built with SwiftUI.

## Features

### 📰 Feed Management
- Subscribe to RSS and Reddit feeds
- Automatic background syncing
- Smart feed categorization
- Mark articles as read/unread
- Favorite articles for later

### 🎨 Customization
- 6 beautiful accent colors
- Light/Dark/System appearance modes
- Serif or Sans-Serif font options
- Configurable short article behavior

### 🔊 Audio Features
- Text-to-speech for articles
- Support for podcast RSS feeds
- Customizable voice selection
- Background audio playback

### 🤖 AI Integration
- AI-powered article summaries
- Chat with AI about articles
- Smart content extraction

### 💻 macOS Features
- Three-column layout optimized for desktop
- Comprehensive keyboard shortcuts
- Menu bar integration
- Window state persistence
- Native macOS Settings window

### 📱 iOS Features
- Adaptive layout (iPhone & iPad)
- Background feed syncing
- Pull to refresh
- Share extensions

## Keyboard Shortcuts (macOS)

### Navigation
- `⌘1` - Today view
- `⌘2` - Manage Feeds
- `⌘3` - AI Summary
- `⌘4` - Settings
- `J` - Next article
- `K` - Previous article
- `←` - Previous image
- `→` - Next image

### Article Actions
- `⌘F` - Toggle favorite
- `⌘U` - Toggle read/unread
- `⌘O` - Open in browser
- `⌘⇧S` - Share article

### Feed Management
- `⌘R` - Sync all feeds
- `⌘⇧K` - Mark all as read

### View
- `⌘+` - Increase text size
- `⌘-` - Decrease text size
- `⌘0` - Reset text size

## System Requirements

### iOS
- iOS 17.0 or later
- iPhone, iPad

### macOS
- macOS 14.0 (Sonoma) or later

## Privacy

Today respects your privacy:
- No user tracking
- No analytics collection
- All data stored locally
- No account required
- Open source

## Technical Details

### Built With
- Swift 6.0
- SwiftUI
- SwiftData for local persistence
- AVFoundation for audio playback
- WebKit for article rendering

### Architecture
- MVVM design pattern
- Reactive data flow with `@AppStorage` and `@Query`
- Background processing with BackgroundTasks framework
- Efficient WebView pooling for performance

## Development

### Building from Source

1. Clone the repository
2. Open `Today.xcodeproj` in Xcode 15+
3. Select your target (iOS or macOS)
4. Build and run (⌘R)

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme Today

# Or use Xcode
Product → Test (⌘U)
```

### Project Structure

```
Today/
├── Models/          # Data models (Feed, Article)
├── Views/           # SwiftUI views
├── Managers/        # Business logic (FeedManager, BackgroundSync)
├── Services/        # External services (AIService)
├── Utilities/       # Helper classes
└── Resources/       # Assets and configurations
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Areas for Contribution
- Additional feed parsers (Atom, JSON Feed)
- More AI providers
- Localization to other languages
- UI/UX improvements
- Bug fixes

## License

[Your License Here - e.g., MIT, GPL-3.0, Apache 2.0]

## Author

**Jake Spurlock**
- Website: [jakespurlock.com](https://jakespurlock.com)
- GitHub: [@whyisjake](https://github.com/whyisjake)
- Twitter: [@whyisjake](https://twitter.com/whyisjake)
- LinkedIn: [jakespurlock](https://linkedin.com/in/jakespurlock)

## Acknowledgments

- Made with ♥️ in California
- Icons by SF Symbols
- Powered by Apple's native frameworks

## Support

If you encounter issues or have questions:
1. Check the [Issues](https://github.com/whyisjake/today/issues) page
2. Submit a new issue with details
3. Contact via [jakespurlock.com](https://jakespurlock.com)

---

**Note:** This is an independent project and is not affiliated with Apple Inc.
