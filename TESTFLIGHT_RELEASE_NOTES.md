# TestFlight Beta Release Notes

## Version 1.13.0 (Build 26)
**Release Date:** August 11, 2026

---

## 🎉 What's New

This release is about speed and reliability rather than new features. The app should feel noticeably better if you have a lot of feeds or a large article library.

### The app stays usable while feeds sync
**Syncing no longer freezes the interface**
- Article insertion, feed parsing and OPML syncing all ran on the main thread — the same thread that draws the UI
- All of it now runs in the background
- Roughly 1.3 seconds of main-thread work removed per sync, measured on a real device
- **What you should notice:** you can scroll and tap articles while a refresh is in progress

### Faster launch with a big library
**Startup no longer slows down as your library grows**
- The app used to load *every* article it had ever downloaded just to show you today's list
- It now loads only the days you're actually looking at
- On a 40,000-article library, list processing went from ~30ms repeated 11 times per launch, to ~11ms once
- **What you should notice:** launch time stays steady over months of use instead of creeping up

### One slow feed no longer holds up the rest
**Feeds refresh independently**
- Feeds were fetched in fixed batches, so a single slow or unreachable feed stalled every feed behind it
- Now a stalled feed occupies one slot while the others carry on
- Requests give up after 15 seconds instead of 60
- On a real 39-feed setup: 148 seconds of total fetch work completed in 34 seconds

### Search is visible again
**The search field on the Today screen no longer hides**
- It used to stay collapsed until you pulled the list down — but that same gesture triggers pull-to-refresh, which usually won
- It's now always visible under the title
- It was also completely unreachable when a filter left the list empty

---

## 🐛 Bug Fixes

### Feeds from an OPML subscription could silently stop updating
This is the significant one.

Feed URLs were compared in the form your OPML file lists them, rather than the form the app stores them in. A feed listed as `http://…` never matched its stored `https://…` record, so every sync marked it as removed — and re-adding it didn't turn it back on.

The result: feeds quietly went inactive and stopped fetching new articles, with nothing in the interface to indicate it.

**Affected feeds are reactivated automatically on your next sync.** On the developer's own device this restored 15 feeds, taking the active feed count from 39 back to 53.

Note that articles published while a feed was inactive won't be backfilled unless the feed still lists them.

### A failed sync blocked retries for two hours
If every feed failed — no signal, airplane mode, a DNS hiccup — the app recorded the sync as successful anyway and then refused to try again for two hours. It now only records success when at least one feed actually responded.

### Temporary redirects could overwrite a feed's URL
A feed temporarily redirected (to a CDN or a maintenance page) had its stored URL permanently rewritten. Only genuinely permanent redirects do that now.

---

## 🧪 What to Focus On

Please try these specifically:

1. **Scroll and tap while a sync is running.** Pull to refresh, then immediately try to scroll and open an article. It should stay responsive throughout — this is the change most likely to be noticeable day to day.

2. **Check your feed list after the first sync.** If you use an OPML subscription, feeds that had stopped updating should be active again. Let us know if any are still missing.

3. **Cold launch.** Force-quit from the app switcher (not just backgrounding) and relaunch. Especially useful if you have a large library.

4. **Search on the Today screen.** It should be visible immediately, and pull-to-refresh should still work normally.

5. **Sync with poor connectivity.** Turn on airplane mode, pull to refresh, then turn it off and pull again. It should retry immediately rather than appearing to succeed and going quiet.

---

## ⚠️ Known Limitations

- **Database indexes only apply to new installations.** Upgrading keeps your existing database, which doesn't gain the new indexes. Queries are still far cheaper than before, but not as fast as a fresh install. A future update will migrate existing databases.
- **Downgrading to 1.12.0 is not supported.** This release adds fields to the database, and the older version cannot open the newer format. If you need to go back, you'll have to delete and reinstall, which loses local data.
- **Adding a newly discovered OPML feed still briefly uses the main thread.** Only happens when your OPML subscription gains a feed, not on a normal sync.

---

## 🙏 Thank You

Your testing and feedback are invaluable. Every bug report, suggestion, and bit of feedback helps make Today better for everyone.

The OPML deactivation bug in this release was found from a device log a tester shared — it had been silently disabling feeds for some time and would have been very hard to spot from the interface alone. Logs help more than you'd think.

Special thanks to:
- **Jonathan Desrosiers** for reporting category capitalization issues
- All beta testers for ongoing feedback
- The RSS community for keeping the open web alive

---

## 📱 Need Help?

- **Documentation:** Check TROUBLESHOOTING.md in the GitHub repo
- **Questions:** Open a discussion on GitHub
- **Urgent issues:** Email jake@jakespurlock.com

Happy testing! 🚀

---

**Build Info:**
- Version: 1.13.0
- Build: 26
- Branch: main
- Commit: [Latest]
