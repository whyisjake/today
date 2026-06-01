---
title: "fix: Eliminate main-thread blocking on cold launch"
type: fix
status: completed
date: 2026-05-31
---

## Summary

The app blocks the main thread for 2+ minutes on cold launch because feed sync, article insertion, and database migration all run on or compete for the main actor during app startup. This plan moves the expensive work off the main thread: article insertion migrates to a background `ModelContext`, `BackgroundSyncManager` loses its class-level `@MainActor` annotation, and both the database migration and default-feed setup are deferred past the first rendered frame.

---

## Problem Frame

On a cold launch with multiple feeds, the app is unusable for 2+ minutes. The SwiftUI first frame blocks because three expensive operations — feed sync orchestration, bulk article insertion, and database migration — run on the main actor simultaneously. `Task.yield()` already exists in the insertion loop as a cooperative yield, but since all insertions still execute on the main actor, the UI can only process events between chunks rather than running freely.

---

## Requirements

- R1. The app must render its first frame within 2 seconds of launch, regardless of how many feeds are subscribed.
- R2. Feed sync must complete in the background without blocking or visibly janking the UI at any point during or after launch.
- R3. Article insertion must not run on the main thread.
- R4. Database migration must not compete with the initial render on first launch.
- R5. The sync behaviour observable to the user (articles appear after sync completes) must not regress.

---

## Scope Boundaries

- This plan does not change the sync logic itself (network requests, parsing, duplicate detection, chunking size).
- This plan does not change the `FeedManager.syncAllFeeds()` path used in `FeedListView` for manual user-triggered syncs — that is a separate concern.
- SwiftData `@Query` view reactivity is not changed; views continue to receive updates automatically when background saves complete.
- No new UI for sync progress indication is added here.

### Deferred to Follow-Up Work

- Removing or consolidating the legacy `FeedManager.syncAllFeeds()` launch path: separate PR once the `BackgroundFeedSync` path is confirmed stable.
- Adding a visible "syncing" progress indicator in `TodayView`: UI work, separate PR.

---

## Context & Research

### Relevant Code and Patterns

- `Today/Services/BackgroundSyncManager.swift` — `@MainActor` class; `performBackgroundSync()`, `triggerManualSync()`, `isSyncInProgress: Bool`
- `Today/Services/BackgroundSyncActor.swift` — `BackgroundFeedSync` enum; `syncAllFeeds(modelContext:)`, `parseAllFeedsInBackground`, `insertArticlesInChunks` (`@MainActor`)
- `Today/Services/FeedManager.swift` — `@MainActor` class; `syncAllFeeds()`, `syncFeedByID()`; the `needsSync()` static check used at launch
- `Today/Services/DatabaseMigration.swift` — `DatabaseMigration.shared.runMigrations()`; `texturizExistingArticles` uses `await MainActor.run {}` for per-article mutation
- `Today/TodayApp.swift` — `addDefaultFeedsIfNeeded()`, `checkAndSyncIfNeeded()`, the `.onAppear` launch sequence; the `DatabaseMigration` task fires here, not in `ContentView`
- `nonisolated` usage on `BackgroundSyncManager.registerBackgroundTasks()` — existing pattern for escaping class-level `@MainActor`
- `ModelContext(container)` off-main pattern — referenced in `CLAUDE.md`; `PersistentIdentifier`-passing already in `BackgroundFeedSync` and `FeedManager.syncFeedByID()`

### Institutional Learnings

- No `docs/solutions/` entries exist yet for SwiftData concurrency; this fix is a good candidate to document once landed.
- `CLAUDE.md` notes: "For background work: Create separate ModelContext from shared ModelContainer" — this is the approved pattern.

### External References

- None needed — local patterns and `CLAUDE.md` are sufficient.

---

## Key Technical Decisions

- **Background `ModelContext` instead of main-context insertion:** `ModelContext(container)` created inside a non-main-actor context is safe to use off-main. Saving from a background context posts `NSPersistentStoreRemoteChangeNotification` which triggers `@Query` observer refresh automatically. This removes bulk I/O from the main actor entirely with no view-layer changes needed.
- **Remove `@MainActor` at the class level from `BackgroundSyncManager`, not from `FeedManager`:** `FeedManager` is a `@StateObject` used directly in `FeedListView` and needs main-actor safety for its `@Published` properties. `BackgroundSyncManager` is a background service; its `@Published isSyncInProgress` and related reads must be gated behind `await MainActor.run {}` individually. The `handleBackgroundSync` method (iOS-only) currently uses `Task { @MainActor in self.handleBackgroundSync(...) }` — removing the class annotation makes this a cross-actor call requiring `await`; update the task closure accordingly.
- **Increase launch sync delay from 500ms to 1500ms:** The existing 500ms delay in `checkAndSyncIfNeeded()` is insufficient — layout and initial `@Query` fetch also compete for the run loop. 1500ms is a safe threshold that lets the first frame fully render before sync starts.
- **`Task(priority: .background)` + 3-second delay for `DatabaseMigration`:** Migration is guarded by `UserDefaults` and is a no-op on all subsequent launches. Deferring by 3 seconds using `.background` priority ensures it does not compete with either the first frame or the initial feed sync.
- **`addDefaultFeedsIfNeeded()` deferred via `Task.detached` with `mainContext` access isolated to `await MainActor.run {}`:** The function currently does synchronous `mainContext` work from `.onAppear`. Moving the feed-count check into `await MainActor.run {}` and the insert/save into a background `ModelContext(container)` (per the U1 pattern) removes the blocking save from the launch critical path while keeping actor-isolation safe.

---

## Open Questions

### Resolved During Planning

- **Can `ModelContext` be safely created and saved from a background thread?** Yes — `ModelContext(container)` (not `container.mainContext`) is the off-main pattern. SwiftData posts change notifications automatically on save.
- **Does removing `@MainActor` from `BackgroundSyncManager` require Swift 6 strict concurrency enabled?** No — the existing codebase uses mixed isolation with `nonisolated` and `await MainActor.run {}`. This pattern is safe in Swift 5.9+ without enabling strict concurrency.
- **Is `feed.articles` relationship faulting safe from a background `ModelContext`?** Yes — relationship faults on a `ModelContext(container)` off-main are supported. However, the GUID dedup set must be validated in tests to confirm no silent empty-set fault produces duplicate inserts.

### Deferred to Implementation

- **Exact delay value for `checkAndSyncIfNeeded()`:** 1500ms is the plan-time recommendation; tune during profiling if needed on slow devices.
- **Whether `insertArticlesInChunks` chunk size (currently 20) should be adjusted for background context:** Likely a no-op since the bottleneck was main-thread contention, not chunk size. Defer to implementation measurement.

---

## Implementation Units

### U1. Move article insertion to a background `ModelContext`

**Goal:** Remove all article `insert` and `save` calls from the main actor. `BackgroundFeedSync.insertArticlesInChunks` currently takes `modelContext: ModelContext` (the main context) and is annotated `@MainActor`. Change it to accept `ModelContainer` and create its own `ModelContext(container)` internally, then save from that off-main context.

**Requirements:** R2, R3, R5

**Dependencies:** None

**Files:**

- Modify: `Today/Services/BackgroundSyncActor.swift`
- Modify: `Today/Services/BackgroundSyncManager.swift` (update call site to pass `container` instead of `container.mainContext`)
- Test: `TodayTests/BackgroundSyncTests.swift` (create if absent)

**Approach:**

- Change `insertArticlesInChunks(parsedFeeds:modelContext:)` signature to `insertArticlesInChunks(parsedFeeds:container:)`. Remove `@MainActor` annotation.
- Inside the function, create `let context = ModelContext(container)` — this is the background context.
- Re-fetch each `Feed` from this background context using `feedData.feedID` before accessing `feed.articles` for GUID dedup — do not carry `Feed` objects across context boundaries.
- Perform all `context.insert()` and `try context.save()` calls on this background context. Remove the `await Task.yield()` between chunks (it was compensating for main-thread contention; on a background context it adds latency with no benefit).
- Update `syncAllFeeds` static method signature from `(modelContext:)` to `(container:)` and thread the container through.
- Update `BackgroundSyncManager.performBackgroundSync()` to pass `self.modelContainer` (the `ModelContainer`) rather than `container.mainContext`.

**Patterns to follow:**

- `FeedManager.syncFeedByID()` — passes `PersistentIdentifier`, creates context as needed; same ownership model.
- `CLAUDE.md`: "For background work: Create separate ModelContext from shared ModelContainer"

**Test scenarios:**

- Happy path: After `syncAllFeeds(container:)` completes, articles inserted by the sync appear in a fresh `ModelContext(container)` fetch — confirms background save was persisted.
- Happy path: The main thread is not blocked during insertion — verify by asserting `Thread.isMainThread == false` inside `insertArticlesInChunks`.
- Edge case: `parsedFeeds` is empty — function returns without error and makes no context operations.
- Edge case: All articles are duplicates of existing GUIDs — no new inserts occur; validate the GUID dedup set is populated (not an empty set from a silent relationship fault on the background context).
- Error path: `context.save()` throws — error is caught and logged, sync continues to the next feed rather than crashing.
- Integration: After sync completes, a `@Query`-backed view receives an update (SwiftData change notification propagated from background save to main context).

**Verification:**

- Instruments Time Profiler shows `insertArticlesInChunks` executing on a non-main thread.
- `@Query` views in `TodayView` refresh with new articles after sync completes.
- No data is lost: article count matches expected value after sync.

---

### U2. Remove class-level `@MainActor` from `BackgroundSyncManager`

**Goal:** `BackgroundSyncManager` is annotated `@MainActor` at the class level, causing all methods — including `performBackgroundSync()` and every `await` resumption — to run on the main thread. Remove the class-level annotation and add granular `@MainActor` isolation only where needed.

**Requirements:** R1, R2

**Dependencies:** U1 (so that the call to `BackgroundFeedSync.syncAllFeeds` inside `performBackgroundSync()` already accepts `container:` rather than `mainContext:`)

**Files:**

- Modify: `Today/Services/BackgroundSyncManager.swift`
- Test: `TodayTests/BackgroundSyncManagerTests.swift` (create if absent)

**Approach:**

- Remove `@MainActor` from the class declaration.
- Annotate `@MainActor` on `@Published var isSyncInProgress: Bool` directly (or move it to an `@MainActor`-isolated extension).
- Replace every direct assignment `self.isSyncInProgress = ...` in `performBackgroundSync()` with `await MainActor.run { self.isSyncInProgress = ... }`. Also wrap the guard-read `guard !isSyncInProgress` in `await MainActor.run { self.isSyncInProgress }` to prevent an unprotected cross-actor read that would be a data race if `triggerManualSync()` is called concurrently.
- Fix `handleBackgroundSync` (iOS-only): it currently creates `Task { @MainActor in self.handleBackgroundSync(...) }`. After removing the class annotation, `self.handleBackgroundSync(task:)` inside the `@MainActor` task closure is a cross-actor call and requires `await`. Update to `Task { await self.handleBackgroundSync(...) }` or restructure the closure isolation.
- `modelContainer` holds a `ModelContainer` (value-type `Sendable`), so no actor annotation needed on that property.
- Confirm `triggerManualSync()` remains callable from a non-actor context. Add `nonisolated` if Swift requires it.
- Verify `registerBackgroundTasks()` and `scheduleBackgroundSync()` remain `nonisolated` (already the case).

**Patterns to follow:**

- `BackgroundSyncManager.registerBackgroundTasks()` — existing `nonisolated` usage on the same class.
- `await MainActor.run {}` blocks elsewhere in the codebase for targeted main-actor hops.

**Test scenarios:**

- Happy path: `triggerManualSync()` can be called from a `Task.detached` context without actor-isolation compiler errors.
- Happy path: `isSyncInProgress` transitions from `false → true → false` across a full sync cycle (observable from a `@MainActor`-bound observer).
- Edge case: `triggerManualSync()` called while `isSyncInProgress == true` — second call is a no-op; the `MainActor.run`-gated guard fires correctly.
- Integration: After removing class-level `@MainActor`, a full sync from `TodayApp.onAppear` completes and articles appear in `TodayView` — confirms the end-to-end path still works.

**Verification:**

- No compiler errors or warnings about actor isolation after the change.
- `performBackgroundSync()` executes on a non-main thread (confirmed via `Thread.isMainThread` assertion or Instruments).
- `isSyncInProgress` is always mutated on the main actor (confirmed via `MainActor.assertIsolated()` in debug builds).

---

### U3. Defer `DatabaseMigration` off the launch critical path

**Goal:** `DatabaseMigration.shared.runMigrations()` fires in a plain `Task {}` from the `.onAppear` modifier in `TodayApp.swift`, which schedules it at default priority — competing directly with initial layout and feed sync. Move it to `Task(priority: .background)` with a 3-second delay so it does not contend with first-frame rendering or initial sync.

**Requirements:** R1, R4

**Dependencies:** None

**Files:**

- Modify: `Today/TodayApp.swift`

**Approach:**

- Locate the `Task { await DatabaseMigration.shared.runMigrations(...) }` call in `TodayApp.swift` (in the `.onAppear` modifier on `ContentView()` inside `WindowGroup`; it is not inside `ContentView` itself).
- Replace with `Task(priority: .background) { try? await Task.sleep(for: .seconds(3)); await DatabaseMigration.shared.runMigrations(...) }`.
- The 3-second delay is intentional: migration is a no-op on all launches after the first, so first-launch users are the only ones affected; the migration running 3 seconds later is unnoticeable.
- No change to `DatabaseMigration` internals — the `UserDefaults` guard already makes it idempotent.

**Patterns to follow:**

- `checkAndSyncIfNeeded()` in `TodayApp.swift` — existing pattern of `Task.detached(priority:)` with a sleep delay before work.

**Test scenarios:**

- Happy path: Migration still runs after the 3-second delay on first launch — `UserDefaults` guard is set after completion.
- Edge case: App is backgrounded before the 3-second delay expires — task is cancelled; migration runs on next foreground launch (idempotent, no data loss).
- Integration: On a fresh install, articles still have the expected `texturizedContent` populated after migration runs (delayed but correct).

**Verification:**

- Instruments Time Profiler shows no `DatabaseMigration` work on the main thread during the first 3 seconds of launch.
- On a repeated cold launch (migration already run), the `UserDefaults` guard fires immediately and no migration work occurs.

---

### U4. Make `addDefaultFeedsIfNeeded()` non-blocking on first launch

**Goal:** On a true cold install, `addDefaultFeedsIfNeeded()` runs synchronous `mainContext` work (feed count fetch, insert, save) in `.onAppear` before the first frame is committed. Defer the DB writes past the first frame by moving work into a `Task.detached`, with `mainContext` accesses isolated to `await MainActor.run {}` and the insert/save moved to a background `ModelContext(container)`.

**Requirements:** R1

**Dependencies:** None

**Files:**

- Modify: `Today/TodayApp.swift`

**Approach:**

- Wrap the call site (in `.onAppear`) in `Task.detached(priority: .userInitiated)` with `try? await Task.sleep(for: .milliseconds(100))` before the work begins.
- Inside the detached task, the feed-count check requires main-context access: wrap it in `await MainActor.run { container.mainContext.fetch(...) }`.
- If zero feeds are found, perform the default-feed insert and save using a background `ModelContext(container)` (same pattern as U1) rather than `mainContext`, to avoid a cross-actor write from the detached task.
- The subsequent sync trigger (currently `Task.detached` that calls `syncAllFeeds`) is already off-main and is unchanged.
- On subsequent launches, the feed-count check returns early after the `await MainActor.run {}` and no inserts occur — the overhead is a single `mainContext` fetch behind a `MainActor.run`.

**Patterns to follow:**

- `checkAndSyncIfNeeded()` — same file, same `Task.detached` + sleep delay pattern.
- U1 background `ModelContext` pattern for the insert/save step.

**Test scenarios:**

- Happy path: On first launch with zero feeds, 14 default feeds are inserted and a sync is triggered — confirmed by checking feed count in a fresh `ModelContext(container)` after the delay.
- Edge case: Feeds already exist — the function exits early after the `MainActor.run` fetch without inserting or saving.
- Edge case: Task is cancelled before completion (app immediately backgrounded) — no partial inserts remain (SwiftData transactional save is atomic).
- Edge case: The 100ms detached insert has not yet completed when the 1500ms sync fires — sync sees zero feeds and is a no-op; default feeds will be picked up on the next sync cycle. This is acceptable on first install and should be noted in a comment at the call site.

**Verification:**

- On first install, `TodayView` renders immediately (within 2 seconds) with an empty article list, then populates as sync completes.
- Feed count is correct after the deferred insert fires.
- No compiler warnings about `@Sendable` capture or cross-actor access from the detached task.

---

## System-Wide Impact

- **Interaction graph:** `BackgroundSyncManager.performBackgroundSync()` is the only caller of `BackgroundFeedSync.syncAllFeeds` at launch. `FeedListView` calls `FeedManager.syncAllFeeds()` for manual refreshes — that path is unchanged.
- **Error propagation:** Background `ModelContext` save failures in U1 should be caught and logged per-feed rather than propagating to abort the entire sync. The existing `do/catch` structure in `BackgroundFeedSync` provides this boundary.
- **State lifecycle risks:** U1 introduces a new background context that saves independently of `container.mainContext`. There is no risk of double-insert because the GUID-based duplicate check runs before insertion; validate this check is not silently bypassed by an empty relationship fault on the background context (see U1 test scenarios).
- **API surface parity:** `BackgroundFeedSync.syncAllFeeds` signature changes from `(modelContext:)` to `(container:)`. The only call site is `BackgroundSyncManager.performBackgroundSync()` — update there. No public API exposed.
- **Integration coverage:** The most critical integration scenario is the end-to-end path: cold launch → `checkAndSyncIfNeeded()` fires → `BackgroundSyncManager.triggerManualSync()` → `BackgroundFeedSync.syncAllFeeds(container:)` → articles appear in `TodayView`. Verify manually after U1 and U2 land.
- **Unchanged invariants:** `FeedManager.syncAllFeeds()` (manual sync from `FeedListView`), the `BGAppRefreshTask` background fetch path, and all `@Query` view subscriptions are unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
| ---- | ---------- |
| Background `ModelContext` save conflicts with main context | SwiftData's persistent store coordinator handles multi-context writes; GUID dedup prevents duplicate inserts |
| Removing `@MainActor` from `BackgroundSyncManager` causes `handleBackgroundSync` compiler error | Addressed explicitly in U2 approach: update the `Task { @MainActor in ... }` closure to use `await` on the cross-actor call |
| Unprotected `isSyncInProgress` read becomes a data race | Addressed in U2: wrap the guard-read in `await MainActor.run {}` alongside the write |
| 1500ms sync delay feels slow on a fast connection | Tunable constant; profile on device and reduce if first-frame render is measurably faster |
| `Task(priority: .background)` for migration gets cancelled on backgrounding | Migration is idempotent; it will complete on the next foreground launch |
| U4 detached insert races with first sync (sees zero feeds) | Acceptable on first install; sync re-runs via background refresh. Note at call site |

---

## Sources & References

- Related code: `Today/Services/BackgroundSyncManager.swift`, `Today/Services/BackgroundSyncActor.swift`, `Today/Services/FeedManager.swift`, `Today/Services/DatabaseMigration.swift`, `Today/TodayApp.swift`
- `CLAUDE.md` background context guidance: "For background work: Create separate ModelContext from shared ModelContainer"
