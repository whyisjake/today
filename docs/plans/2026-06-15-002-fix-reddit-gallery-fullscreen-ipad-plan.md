---
title: "fix: Open Reddit gallery images full screen on iPad"
type: fix
status: active
date: 2026-06-15
---

# fix: Open Reddit gallery images full screen on iPad

## Summary

On iPad, tapping a Reddit gallery image opens `FullScreenImageGallery` as a `.sheet`, which renders as a card-style modal rather than occupying the full display. Changing the iOS presentation to `.fullScreenCover` makes the gallery cover the entire screen, matching expected full-screen image viewer behavior.

---

## Problem Frame

On iPad, `.sheet` presentations appear as a floating card over the content behind it. For an image gallery, this wastes screen real estate and breaks the immersive feel. `.fullScreenCover` covers the entire display, which is the appropriate treatment for a full-screen image viewer.

---

## Requirements

- R1. Tapping a Reddit gallery image on iPad (and iPhone) opens the gallery covering the full screen.
- R2. The existing "Done" button and all gallery functionality (zoom, pan, swipe, share) remain intact.
- R3. The black background and navigation bar continue to render correctly.

---

## Scope Boundaries

- macOS gallery sheet presentation is not changed.
- No changes to `FullScreenImageGallery` view internals.
- No changes to zoom, pan, video playback, or share behavior.

---

## Context & Research

### Relevant Code and Patterns

- `Today/Views/RedditPostView.swift` lines 986–991 — the iOS `.sheet` modifier on `ImageGalleryView`
- `FullScreenImageGallery` already has `@Environment(\.dismiss)` and a "Done" toolbar button — dismissal works correctly with both `.sheet` and `.fullScreenCover`
- `.presentationDragIndicator(.visible)` and `.presentationBackground(.black)` are sheet-specific modifiers and must be removed; `FullScreenImageGallery` already applies `platformBackgroundColor` (black) to its own background

### Key Observations

- `FullScreenImageGallery` uses `.ignoresSafeArea()` — already prepared for edge-to-edge display
- The view is wrapped in a `NavigationStack` with a visible toolbar, so status bar overlap is handled correctly under `.fullScreenCover`
- Swipe-to-dismiss is not available with `.fullScreenCover` by default; the "Done" button is the primary dismiss path, which is already in place

---

## Key Technical Decisions

- **`.fullScreenCover` over `.sheet`**: Covers the entire screen on all iOS/iPadOS devices. No additional configuration needed — the existing view is already built for full-screen display.
- **Remove sheet-specific modifiers**: `.presentationDragIndicator(.visible)` and `.presentationBackground(.black)` are no-ops on `.fullScreenCover` and produce a compiler warning; removing them is correct.
- **No swipe-to-dismiss**: `.fullScreenCover` does not support the pull-down swipe-to-dismiss gesture that `.sheet` provides. The "Done" button is sufficient and already implemented.

---

## Implementation Units

### U1. Replace `.sheet` with `.fullScreenCover` for iOS gallery presentation

**Goal:** Make the Reddit gallery open full screen on iOS/iPadOS instead of as a modal card.

**Requirements:** R1, R2, R3

**Dependencies:** None

**Files:**
- Modify: `Today/Views/RedditPostView.swift`

**Approach:**
- In the `#if os(iOS)` block of `ImageGalleryView` (around line 987), replace `.sheet(isPresented: $showFullScreen)` with `.fullScreenCover(isPresented: $showFullScreen)`
- Remove the `.presentationDragIndicator(.visible)` and `.presentationBackground(.black)` modifiers from the presented view — they are sheet-only APIs and do not apply to `fullScreenCover`
- No changes inside `FullScreenImageGallery` itself

**Patterns to follow:**
- The existing macOS path uses `.sheet` with explicit sizing — leave it untouched
- `FullScreenImageGallery` already handles its own background and dismiss button

**Test scenarios:**
- Happy path: Tap any image in a Reddit gallery on an iPad simulator → gallery opens covering the full screen with no visible content behind it
- Happy path: Tap "Done" button → gallery dismisses and article content returns
- Happy path: On iPhone → gallery also opens full screen (behavior improved there too)
- Edge case: Gallery with a single image → opens full screen, "1 of 1" title shows correctly
- Edge case: Gallery with animated GIF/video → video plays correctly in full-screen cover
- Regression: macOS gallery sheet behavior unchanged

**Verification:**
- On iPad simulator, tapping a gallery image shows `FullScreenImageGallery` edge-to-edge with no card shadow or sheet drag indicator
- "Done" button dismisses correctly
- Zoom, pan, swipe between images, and share sheet all function as before

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Loss of swipe-to-dismiss | "Done" button already present and functional; acceptable trade-off for full-screen UX |
| Sheet-specific modifiers causing warnings if not removed | Remove both modifiers as part of this change |

---

## Sources & References

- Implementation file: `Today/Views/RedditPostView.swift` (lines 986–1011)
- Gallery view: `FullScreenImageGallery` struct (lines 1017–)
