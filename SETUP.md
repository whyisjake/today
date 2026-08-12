# Setup Instructions for Today RSS Reader

Getting a development build running locally.

## Requirements

- **macOS with Xcode 16 or later** — the project builds against the iOS 26 SDK
- **iOS 18.0+** deployment target (iPhone and iPad)
- **macOS 15.6+** for the macOS target
- No package manager step: the only dependency, [OutcastID3](https://github.com/CrunchyBagel/OutcastID3), resolves automatically through Swift Package Manager on first open

## Build and run

```bash
git clone git@github.com:whyisjake/today.git
cd today
open Today.xcodeproj
```

Press `Cmd+R` to run, `Cmd+U` to test.

From the command line:

```bash
# See which simulators you actually have
xcrun simctl list devices available

# Build and test (substitute a simulator from the list above)
xcodebuild build -project Today.xcodeproj -scheme Today \
  -destination 'platform=iOS Simulator,name=iPhone 17'

xcodebuild test -project Today.xcodeproj -scheme Today \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# The macOS target shares most of the source — build it too before pushing
xcodebuild build -project Today.xcodeproj -scheme "Today MacOS" \
  -destination 'platform=macOS'
```

## Adding files

**You don't need to add files to the Xcode project.** `Today/`, `TodayTests/` and the macOS
targets are all *synchronized folder groups*, so anything you create on disk in those
directories joins the target automatically.

Manually adding files through Xcode's "Add Files to Today…" will create duplicate references.
If a new file genuinely isn't being compiled, check it's inside one of the synchronized
directories rather than reaching for the project navigator.

## Background fetch

Already configured — the `com.today.feedsync` task identifier and the Background Modes
capability are part of the project. Nothing to set up.

To exercise it: run the app, then in Xcode use **Debug → Simulate Background Fetch**. iOS
decides when real background tasks run, so this is the only reliable way to trigger one on
demand.

For the sync path more generally, the DEBUG launch arguments are usually more useful — see
`CLAUDE.md` under "Measuring performance" for `-ForceSyncOnLaunch`, `-SeedLargeStore` and
`-ResetArticlesOnLaunch`.

## Getting started with the app

1. **Add RSS feeds** — "Feeds" tab → "+" → paste a feed URL. Some to try:
   - Daring Fireball: `https://daringfireball.net/feeds/main`
   - Hacker News: `https://news.ycombinator.com/rss`
   - The Verge: `https://www.theverge.com/rss/index.xml`
2. **Add a subreddit** — choose "Reddit" in the feed picker and enter just the name
   (`swift`, not a full URL)
3. **Import an OPML file** — Settings → Import, or subscribe to a remote OPML URL that stays
   in sync
4. **Pull to refresh** on the Today tab, or `Cmd+R` on macOS

A first launch with no feeds seeds a default set, then syncs.

## Before you push

```bash
xcodebuild test -project Today.xcodeproj -scheme Today \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -project Today.xcodeproj -scheme "Today MacOS" -destination 'platform=macOS'
```

Read **CLAUDE.md** first if you're touching background work or SwiftData queries. This project
builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY`,
which make isolation behave unintuitively — `nonisolated` alone does *not* move `async` work
off the main thread, and that has silently caused a regression before.

## Troubleshooting

- **"No such simulator"** — the destination name is wrong for your machine. Run
  `xcrun simctl list devices available` and use one from the list.
- **A new file isn't compiling** — it's probably outside a synchronized folder. Move it under
  `Today/` or `TodayTests/` rather than adding it via Xcode.
- **Stale data or a schema error after switching branches** — delete the app from the
  simulator and rerun. Note that model changes are forward-only: a build with fewer model
  properties cannot open a store written by a newer one, and the app calls `fatalError` if the
  container fails to open.
- **Package resolution fails** — File → Packages → Reset Package Caches.

See `TROUBLESHOOTING.md` for runtime issues, and `RELEASE_PROCESS.md` for shipping.
