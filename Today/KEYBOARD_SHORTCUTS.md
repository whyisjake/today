# Keyboard Shortcuts Guide

This document provides a comprehensive list of all keyboard shortcuts available in the Today app on macOS.

## Navigation Shortcuts

### Sidebar Navigation
- **⌘1** - Navigate to Today view
- **⌘2** - Navigate to Manage Feeds
- **⌘3** - Navigate to AI Summary
- **⌘4** - Navigate to Settings

### Article Navigation
- **J** - Next article (like Gmail/Reddit)
- **K** - Previous article (like Gmail/Reddit)
- **Space** - Scroll article page down, then advance to next article when at bottom

### Image Navigation (in articles with galleries)
- **←** - Previous image
- **→** - Next image

## Article Actions

### Reading & Organization
- **⌘F** - Toggle favorite/star on current article
- **⌘U** - Toggle read/unread status on current article

### Sharing & Browsing
- **⌘O** - Open current article in external browser (Safari)
- **⌘⇧S** - Share current article (opens system share sheet)

## Feed Management

### Sync & Organization
- **⌘R** - Sync all feeds (refresh content)
- **⌘⇧K** - Mark all articles as read

## View Adjustments

### Text Size (in article view)
- **⌘+** - Increase text size
- **⌘-** - Decrease text size  
- **⌘0** - Reset text size to default

## Standard macOS Shortcuts

### Text Editing (when text is selected)
- **⌘C** - Copy selected text
- **⌘A** - Select all text

## Tips & Tricks

### Vi-style Navigation
The app uses **J/K** navigation inspired by Vi/Vim editors, commonly found in:
- Gmail (navigate emails)
- Reddit (navigate posts)
- Twitter/X (navigate tweets)
- Many developer tools

This allows for quick one-handed navigation through articles without leaving the home row.

### Quick Workflow Examples

**Speed reading with Space bar (Google Reader style):**
1. Select an article
2. Press **Space** repeatedly to page through the article
3. When you reach the bottom, Space automatically advances to the next article
4. Continue pressing Space to flow through your reading list

**Triaging articles:**
1. Press **J** to go to next article
2. Press **⌘F** to favorite interesting ones
3. Articles are automatically marked as read when viewed
4. Use **⌘U** to mark something unread for later

**Reading session:**
1. Press **⌘1** to go to Today view
2. Use **J/K** to navigate articles, or **Space** to page through
3. Press **⌘O** to open interesting articles in browser
4. Press **⌘⇧K** when done to mark all as read

**Organizing feeds:**
1. Press **⌘2** to open Manage Feeds
2. Press **⌘R** to sync all feeds
3. Press **⌘1** to return to Today view

## Implementation Notes

All keyboard shortcuts are implemented using:
- Native SwiftUI `CommandMenu` for menu bar integration
- Notification-based system for cross-view communication
- View modifiers for clean, reusable code
- Platform-specific compilation (`#if os(macOS)`) for macOS-only features

The shortcuts are designed to:
- Feel native to macOS
- Match conventions from popular apps (Gmail, Reddit)
- Allow for efficient one-handed operation
- Be discoverable through the menu bar

---

*Last updated: February 3, 2026*
