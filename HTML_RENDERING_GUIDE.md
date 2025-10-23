# HTML Rendering in RSS Feeds

## Problem
RSS feeds often include HTML markup in article descriptions, like:
```
<p>This is a <strong>great</strong> article about <a href="...">SwiftUI</a></p>
```

Without proper handling, this displays as raw text with tags visible.

## Solution Implemented

I've added native HTML rendering using SwiftUI's `AttributedString`. This gives you:

✅ **Proper formatting** - Bold, italic, underline all work
✅ **Native look** - Matches iOS design perfectly
✅ **Links** - Clickable links in text (though tapping opens the article)
✅ **No WebView needed** - Lightweight and fast
✅ **Fallback handling** - If HTML parsing fails, strips tags gracefully

## What Was Added

### 1. HTML Helper Utilities (`Utilities/HTMLHelper.swift`)

**Three useful extensions on String:**

```swift
// Converts HTML to formatted AttributedString
"<p>Hello <b>world</b></p>".htmlToAttributedString

// Strips all HTML tags for plain text
"<p>Hello <b>world</b></p>".htmlToPlainText  // "Hello world"

// Quick check for HTML content
"<p>Hello</p>".strippingHTML
```

**Common HTML entities are decoded:**
- `&nbsp;` → space
- `&amp;` → &
- `&lt;` → <
- `&gt;` → >
- `&quot;` → "
- `&#39;` → '

### 2. Updated Article Display Views

**TodayView.swift** - Now uses:
```swift
Text(description.htmlToAttributedString)
```

Instead of:
```swift
Text(description)
```

This happens in:
- Article row previews (2-line limit)
- Article detail descriptions (full text)

### 3. Enhanced Article Reader (`Views/ArticleWebView.swift`)

**New feature!** You can now:
- **Read in App** - Opens full article in embedded WebView
- **Open in Safari** - Original behavior

The WebView includes:
- Back/forward gestures
- Phone number and link detection
- Close button to return to description
- Safari button to open externally

## How It Works

### Rendering Process:
1. **Try AttributedString HTML parsing** (iOS 15+, works great)
2. **Fall back to NSAttributedString** (older method, very reliable)
3. **Fall back to plain text** (strips all HTML if parsing fails)

### AI Processing:
The AI service uses `.htmlToPlainText` so it analyzes actual content, not HTML tags.

## Testing

Try these RSS feeds that have lots of HTML:

1. **Daring Fireball** - `https://daringfireball.net/feeds/main`
   - Rich formatting, italics, links

2. **The Verge** - `https://www.theverge.com/rss/index.xml`
   - Images, complex HTML

3. **Ars Technica** - `https://feeds.arstechnica.com/arstechnica/index`
   - Inline code, formatting

## Files Changed

✅ **New:** `Utilities/HTMLHelper.swift` - HTML conversion utilities
✅ **New:** `Views/ArticleWebView.swift` - In-app article reader
✅ **Updated:** `Views/TodayView.swift` - Uses HTML rendering
✅ **Updated:** `Services/AIService.swift` - Uses plain text for analysis

## Usage Examples

### In Your Code:

```swift
// Display HTML in any SwiftUI view
Text(htmlString.htmlToAttributedString)

// Or use the helper view
HTMLText(htmlString, fontSize: 16)

// Get plain text for processing
let plainText = htmlString.htmlToPlainText
```

### Custom Styling:

```swift
// The AttributedString preserves HTML styles
// You can override with SwiftUI modifiers:
Text(html.htmlToAttributedString)
    .foregroundStyle(.primary)  // Override color
    .font(.body)                // Override font
```

## Benefits

1. **Better UX** - Articles look professional and formatted
2. **Native Performance** - No WebView overhead for descriptions
3. **Accessibility** - VoiceOver reads formatted text correctly
4. **Fallback Safety** - Never crashes on malformed HTML
5. **In-App Reading** - Optional WebView for full articles

## Troubleshooting

**"Still seeing HTML tags"**
- Make sure you added `Utilities/HTMLHelper.swift` to your Xcode project
- Clean build (Shift+Cmd+K) and rebuild

**"Links don't work"**
- In article rows, links aren't clickable (by design - tapping opens article)
- In the WebView reader, all links work normally

**"Formatting looks wrong"**
- Some RSS feeds have broken HTML
- The fallback strips tags and shows plain text
- This is expected behavior for malformed HTML

**"Images don't show in descriptions"**
- SwiftUI's AttributedString doesn't render `<img>` tags
- Use "Read in App" button to see full article with images
- This is a limitation of native text rendering

## Advanced: Custom HTML Rendering

If you want more control over HTML rendering, you can modify `HTMLHelper.swift`:

```swift
// Add custom CSS
let html = """
<style>
    body { font-family: -apple-system; color: #333; }
    a { color: #007AFF; }
</style>
\(htmlString)
"""
```

Or implement a custom NSAttributedString parser with your own styling rules.

## Next Steps

The HTML rendering is now automatic. Just:
1. Add the new files to your Xcode project
2. Build and run
3. Add RSS feeds
4. Enjoy properly formatted content!

No configuration needed - it just works! 🎉
