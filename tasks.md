# ListenUp — Project Review & Staged Task Roadmap

This document tracks all bugs, performance optimizations, architectural improvements, and usability enhancements identified during the full codebase review of **ListenUp** (iOS, watchOS, CarPlay, and WidgetKit targets).

Tasks are organized into **5 actionable stages** ordered by severity and user impact so they can be tackled incrementally.

---

## Stage 1: Critical Bugs & Functional Defects

High-priority bugs that cause broken user flows, lost listening stats, silent failures, or race conditions.

- [x] **1.1 Fix Synchronous ZIP Export Running Inside SwiftUI `body`**
  - **Location:** `ListenUp/Views/ListeningHistoryBackupSheet.swift` (`cloudExportCard`, lines 273–277)
  - **Issue:** `ListeningHistoryBackupService.createExportPayload(from: allItems)` is invoked directly inside the view's `body` evaluation to feed `ShareLink`. Every SwiftUI state change or re-render runs synchronous disk I/O, JSON encoding, artwork writing, and `NSFileCoordinator` ZIP compression on the `@MainActor`, causing severe UI stalls.
  - **Fix:** Replace eager `ShareLink(item: url)` generation with a `Transferable` wrapper that builds the archive lazily on export, or pre-build the archive asynchronously inside a background `Task` when the user taps an explicit "Prepare Archive" / "Export to Files" action.

- [x] **1.2 Fix External Audio File Open-In (`file://` URLs Ignored)**
  - **Location:** `ListenUp/Info.plist` (lines 27–43), `ListenUp/ListenUpApp.swift` (line 42), `ListenUp/Services/NavigationCoordinator.swift` (`handleURL(_:)`, line 18)
  - **Issue:** `Info.plist` declares support for opening audio files (`public.audio`, `.m4b`, `.mp3`, etc.) and `LSSupportsOpeningDocumentsInPlace`, and `ListenUpApp` forwards `.onOpenURL` to `NavigationCoordinator.handleURL`. However, `handleURL` immediately exits unless `url.scheme == "listenup"`, silently dropping `file://` URLs from AirDrop or the Files app's "Open in ListenUp" action.
  - **Fix:** Detect `url.isFileURL` in `ListenUpApp` / `NavigationCoordinator` and route external file URLs directly into `FileImporterService.importURL(_:into:)` on a background task.

- [x] **1.3 Record Daily Listening Stats When Syncing Offline Watch Playback**
  - **Location:** `ListenUp/ListenUpApp.swift` (`setupSyncCallbacks`, lines 75–91)
  - **Issue:** When the user listens offline on Apple Watch and `PlaybackSyncPayload` syncs back to iPhone, `ListenUpApp` updates `item.currentPosition = payload.currentPosition`, `item.lastUpdated`, and `item.isCompleted`, but never calls `ListeningStatsStore.shared.recordListening(seconds:)`. Offline Watch sessions never count toward Today's listening time, weekly charts, or daily goals.
  - **Fix:** Compute the positive delta (`max(0, payload.currentPosition - item.currentPosition)`) before updating `item.currentPosition` (or include an explicit `listenedDeltaSeconds` in `PlaybackSyncPayload`) and record it via `ListeningStatsStore.shared.recordListening(seconds:)` and `WidgetDataStore.shared.syncStats(...)`.

- [x] **1.4 Fix Watch "Play on iPhone" Ignoring the Selected Book**
  - **Location:** `ListenUpWatch/Views/WatchBookDetailView.swift` (lines 87, 125, 151), `ListenUp/Services/WatchSyncManager.swift` (`WatchRemoteCommand`, lines 78–83), `ListenUp/ListenUpApp.swift` (`onRemoteCommandReceived`, lines 93–118)
  - **Issue:** Tapping "Play on iPhone" in `WatchBookDetailView` sends `WatchRemoteCommand(type: .play, value: nil)` without a `bookID`. On iPhone, `.play` only calls `player.resume()` on whatever item happens to be currently loaded (or does nothing if `currentItem` is `nil`), completely ignoring the book the user selected on Watch.
  - **Fix:** Add `bookID: UUID?` to `WatchRemoteCommand`. When `.play` includes a `bookID` that differs from `player.currentItem?.id`, fetch that `LibraryItem` from `ModelContext` and call `player.loadAndPlay(item)` before switching to the Now Playing view.

- [x] **1.5 Scope `AVPlayerItem.didPlayToEndTimeNotification` Observer to Active Player Items**
  - **Location:** `ListenUp/Services/AudioPlayerManager.swift` (lines 696–705), `ListenUp/Services/WatchAudioPlayerManager.swift` (lines 332–340)
  - **Issue:** Both audio managers register for `.AVPlayerItemDidPlayToEndTime` with `object: nil`. Any `AVPlayerItem` finishing anywhere in the process (or a stale item from a previous queue) triggers `handleTrackEnded()`, potentially advancing chapters or marking the active book as completed prematurely.
  - **Fix:** In the notification handler, verify that `guard let finishedItem = notification.object as? AVPlayerItem, playerItems.contains(finishedItem) else { return }` before invoking `handleTrackEnded()`.

- [x] **1.6 Prevent `WCSession.updateApplicationContext` Payload Clobbering**
  - **Location:** `ListenUp/Services/WatchSyncManager.swift` (lines 421, 444, 504), `ListenUp/ListenUpApp.swift` (lines 141–142)
  - **Issue:** `broadcastRemotePlaybackState`, `broadcastLibraryCatalog`, and `sendSyncPayload` each call `session.updateApplicationContext(["msgType": ..., "data": ...])`, which replaces the entire context dictionary. In `ListenUpApp`, calling `broadcastLibraryCatalogToWatch()` followed immediately by `broadcastPlaybackStateToWatch()` overwrites the library catalog in `applicationContext` before an unreachable Watch ever wakes up to receive it.
  - **Fix:** Merge keys into `session.applicationContext` Keyed by message type (e.g., `"catalogData"`, `"remoteStateData"`, `"syncPayloadData"`) so catalog, playback state, and position updates coexist in `applicationContext` without overwriting each other.

---

## Stage 2: Performance, Battery & Memory Optimization

Optimizations to eliminate main-thread blocking, reduce memory footprint, and preserve WidgetKit's daily refresh budget.

- [ ] **2.1 Throttle Widget Reloads and Avoid Re-Downsampling Artwork Every 5 Seconds**
  - **Location:** `ListenUp/ListenUpApp.swift` (`onPositionUpdated`, line 48; `syncActivePlayerToWidget`, lines 173–196), `ListenUp/Shared/WidgetDataStore.swift` (`syncPlayback`, lines 179, 191)
  - **Issue:** During playback, `onPositionUpdated` fires every 5 seconds on `@MainActor` and calls `WidgetDataStore.shared.syncPlayback(...)` with `immediateReload: true` (the default). This synchronously runs `CGImageSource` thumbnail generation on the main thread and calls `WidgetCenter.shared.reloadAllTimelines()` every 5 seconds, bypassing `reloadWidgetsThrottled()` (60s throttle) and exhausting iOS's daily WidgetKit reload budget.
  - **Fix:**
    1. Pass `immediateReload: false` during periodic 5-second position ticks and only use `immediateReload: true` on play/pause state transitions or book changes.
    2. Cache the downsampled artwork `Data` in memory keyed by `bookID` so `downsampleImage` only runs when `currentItem` changes.

- [ ] **2.2 Eliminate N+1 Full-Table Queries and Redundant Saves During Multi-Part Import**
  - **Location:** `ListenUp/Services/FileImporterService.swift` (`persist(dto:into:parent:)`, lines 375–428)
  - **Issue:** `persist(dto:into:parent:)` executes `try context.fetch(FetchDescriptor<LibraryItem>())` (fetching every item in the database into memory) and calls `try context.save()` on every recursive call. Importing a 100-track Pimsleur course performs 101 full-table fetches and 101 SQLite commits on `@MainActor`.
  - **Fix:** Perform duplicate detection only for the root item (using a targeted `#Predicate` on `title` and `parent == nil`), insert the entire parent/child hierarchy in memory, and perform a single `try context.save()` at the end of the import operation.

- [ ] **2.3 Add In-Memory Thumbnail Cache (`NSCache`) for `ArtworkImageView`**
  - **Location:** `ListenUp/Views/Components/ArtworkImageView.swift` (line 30)
  - **Issue:** `ArtworkImageView` calls `UIImage(data: data)` directly inside `body`. Scrolling through `LibraryView`, `SearchView`, or `ProfileView` repeatedly decodes full-resolution cover art on the main thread.
  - **Fix:** Introduce an `NSCache<NSString, UIImage>` (keyed by item `UUID` + target size bucket) or decode/downsample images asynchronously via `.task(id:)` into a `@State` `UIImage`.

- [ ] **2.4 Optimize SwiftData `@Query` Predicates and Sorting**
  - **Location:** `ListenUp/Views/LibraryView.swift` (lines 20–34), `ListenUp/Views/ProfileView.swift` (lines 13–17), `ListenUp/Views/SearchView.swift` (lines 11, 71–78)
  - **Issue:** Views use bare `@Query private var allItems: [LibraryItem]` without predicates or sort descriptors, loading every child track and soft-deleted tombstoned item into memory on every view evaluation, and `LibraryView` does not sort root items deterministically.
  - **Fix:** Add `#Predicate<LibraryItem>` filters (e.g., `$0.isDeleted == false && $0.parent == nil` for root library queries) and explicit `SortDescriptor`s directly on `@Query`.

- [ ] **2.5 Move Synchronous Disk I/O Off the Main Thread**
  - **Location:** `ListenUpWatch/Views/WatchDownloadsView.swift` (line 17), `ListenUp/Services/WatchLibraryStore.swift` (`totalStorageUsedBytes`, lines 196–213), `ListenUp/Models/LibraryItem.swift` (`resolvedURL`, lines 145–175)
  - **Issue:** `WatchDownloadsView` calls `libraryStore.totalStorageUsedBytes()` directly inside `body`, enumerating the filesystem on every render. Similarly, `LibraryItem.resolvedURL()` performs up to 3 `FileManager.default.fileExists` checks synchronously whenever `isFileOffloaded` is read by `LibraryRow`.
  - **Fix:** Compute and cache storage usage asynchronously in `WatchLibraryStore` when books are added/removed, and cache file existence state or update it only on import/offload/foreground events.

- [ ] **2.6 Debounce CarPlay Template Rebuilds**
  - **Location:** `ListenUp/CarPlay/CarPlayTemplateManager.swift` (lines 107–126)
  - **Issue:** `CarPlayTemplateManager` observes both `playbackStateDidChangeNotification` and `ModelContext.didSave`. Because playback progress saves `ModelContext` every 5 seconds, CarPlay re-fetches all `LibraryItem`s and rebuilds the `CPTabBarTemplate` hierarchy every 5 seconds while driving.
  - **Fix:** Debounce template updates, separate play/pause indicator updates on existing `CPListItem`s from full hierarchy rebuilds, and ignore `didSave` notifications triggered solely by 5-second `currentPosition` ticks.

- [ ] **2.7 Reuse `DateFormatter` in `LibraryItem.formattedCompletedDate`**
  - **Location:** `ListenUp/Models/LibraryItem.swift` (lines 150–155)
  - **Issue:** `formattedCompletedDate` allocates a new `DateFormatter()` on every property access inside `LibraryRow` and `ProfileView`.
  - **Fix:** Use a static cached `DateFormatter` or Swift's modern `completedDate.formatted(date: .abbreviated, time: .omitted)`.

---

## Stage 3: Feature Completeness & Settings Wiring

Features that have UI controls or badges present in the codebase but are currently unhooked or hardcoded.

- [ ] **3.1 Wire Up Default Sleep Timer Setting in `AudioPlayerManager`**
  - **Location:** `ListenUp/Views/SettingsView.swift` (lines 15, 61), `ListenUp/Services/AudioPlayerManager.swift` (`loadAndPlay`, `resume`)
  - **Issue:** `SettingsView` persists `@AppStorage("defaultSleepTimerMinutes")`, and `ListenUpTests` tests the UserDefaults key, but `AudioPlayerManager` never reads `defaultSleepTimerMinutes` when starting playback.
  - **Fix:** In `AudioPlayerManager.loadAndPlay` (and optionally `resume` when no timer is active), check `UserDefaults.standard.integer(forKey: "defaultSleepTimerMinutes")` and automatically call `setSleepTimer(minutes:)` if `> 0` and `sleepTimerRemaining == nil`.

- [ ] **3.2 Implement Real Streak Calculation for Widgets and Profile**
  - **Location:** `ListenUp/Services/ListeningStatsStore.swift` (line 162), `ListenUp/Shared/WidgetDataStore.swift` (line 239)
  - **Issue:** `ListeningStatsStore` never computes consecutive listening days and calls `WidgetDataStore.shared.syncStats(...)` relying on the default parameter `streakDays: Int = 1`. The widget always displays a 1-day streak even with 0 listening history or a 30-day streak.
  - **Fix:** Add a `currentStreakDays` computation in `ListeningStatsStore` by walking backward from today/yesterday through `dailyHistory` where `seconds > 0`, and pass it to `WidgetDataStore.shared.syncStats`.

- [ ] **3.3 Implement Smooth Audio Fade-Out and `Date`-Based Sleep Timer**
  - **Location:** `ListenUp/Services/AudioPlayerManager.swift` (`setSleepTimer`, lines 785–798)
  - **Issue:** The sleep timer decrements `sleepTimerRemaining` by 1 every `Task.sleep(nanoseconds: 1_000_000_000)` (which drifts over long periods) and immediately calls `pause()` despite the comment `// Time expired: smooth fadeout and pause`.
  - **Fix:** Compute remaining time from a target `Date` deadline (`sleepTimerEndDate.timeIntervalSinceNow`), and ramp `queuePlayer.volume` down smoothly over the final 5 seconds before calling `pause()` and restoring `queuePlayer.volume = 1.0`.

- [ ] **3.4 Track "Nighttime Listener" Milestone Dynamically**
  - **Location:** `ListenUp/Views/ProfileView.swift` (line 540), `ListenUp/Services/AudioPlayerManager.swift`
  - **Issue:** The "Nighttime Listener" badge in `ProfileView` has `isUnlocked: true` hardcoded.
  - **Fix:** Persist a boolean or counter in `UserDefaults` (`hasUsedSleepTimer` / `sleepTimersCompletedCount`) when a sleep timer finishes or is activated, and bind the milestone badge to that value.

- [ ] **3.5 Unify and Persist Playback Speed Across App Relaunches, Lock Screen, and Watch**
  - **Location:** `ListenUp/Views/PlaybackSpeedMenu.swift` (line 7), `ListenUp/Services/AudioPlayerManager.swift` (lines 87, 486, 940), `ListenUpWatch/Views/WatchNowPlayingView.swift` (line 206)
  - **Issue:**
    1. `PlaybackSpeedMenu` includes `2.5x`, which is missing from `AudioPlayerManager.cyclePlaybackRate()`, `MPRemoteCommandCenter.changePlaybackRateCommand.supportedPlaybackRates`, and `WatchNowPlayingView`.
    2. `playbackRate` always resets to `1.0x` on app launch instead of remembering the user's preferred speed (or per-book speed).
  - **Fix:** Define a single shared `PlaybackSpeed.supportedRates` array (`[0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5]`), persist the selected rate in `UserDefaults` (or per `LibraryItem`), and restore it when configuring `AudioPlayerManager`.

- [ ] **3.6 Handle `listenup://library` Deep Link in `NavigationCoordinator`**
  - **Location:** `ListenUpWidgets/PlayerWidget.swift` (line 228), `ListenUp/Services/NavigationCoordinator.swift` (`handleURL`, lines 22–62)
  - **Issue:** `SmallPlayerWidgetView.emptyStateView` links to `listenup://library`, which hits `default: break` in `NavigationCoordinator.handleURL`.
  - **Fix:** Add `case "library": selectedTab = .library; isFullPlayerPresented = false` to `NavigationCoordinator.handleURL`.

- [ ] **3.7 Prefix Watch Transferred Multi-Part Track Filenames with `partIndex`**
  - **Location:** `ListenUp/Services/WatchSyncManager.swift` (line 718), `ListenUp/Services/WatchLibraryStore.swift` (lines 115, 157)
  - **Issue:** Multi-part tracks transferred to Apple Watch are saved using `file.url.lastPathComponent` and later reconstructed by sorting filenames alphabetically (`<`). If source files have non-zero-padded names (`Track 2.mp3` vs `Track 10.mp3`) or identical filenames from different subfolders, playback order on Watch will be corrupted or files will overwrite each other.
  - **Fix:** Prefix destination filenames on Watch with a zero-padded `partIndex` (e.g., `String(format: "%04d_%@", partIndex, originalFilename)`).

- [ ] **3.8 Configure CloudKit Entitlements & Dynamic Sync Status in `SettingsView`**
  - **Location:** `ListenUp/ListenUp.entitlements`, `ListenUp/Services/AppDatabase.swift` (line 31), `ListenUp/Views/SettingsView.swift` (line 121)
  - **Issue:** `ListenUp.entitlements` only contains the App Group (`group.com.SmartApps.ListenUp`) and lacks `com.apple.developer.icloud-services` / `com.apple.developer.icloud-container-identifiers`. As a result, `AppDatabase` falls back to a local-only `ModelContainer` when CloudKit initialization fails, while `SettingsView` hardcodes `"iCloud SwiftData Sync: Active"`.
  - **Fix:** Add the required iCloud/CloudKit container entitlements, expose a `var isCloudKitActive: Bool` flag on `AppDatabase`, and reflect the actual sync state in `SettingsView`.

- [ ] **3.9 Fix Total Listening Time Fallback Calculation**
  - **Location:** `ListenUp/Views/ProfileView.swift` (`totalListeningSeconds`, lines 821–825), `ListenUp/Services/ListeningStatsStore.swift` (lines 345–349)
  - **Issue:** `ProfileView.totalListeningSeconds` sums `currentPosition` across `allItems` (which includes child tracks if any had non-zero positions) and inflates listening time if a user scrubs to the end of a book without actually listening.
  - **Fix:** Filter by root items (`$0.parent == nil`) when computing book-position fallbacks, and prefer `ListeningStatsStore.totalHistoricalSeconds` as the primary source of truth.

---

## Stage 4: Usability & UX Enhancements

Improvements to core user workflows across library management, search, player controls, and Apple Watch.

- [ ] **4.1 Allow Re-Importing / Relinking Offloaded Books**
  - **Location:** `ListenUp/Views/LibraryView.swift` (lines 130–135, 208–219), `ListenUp/Views/Components/LibraryRow.swift` (lines 154–202)
  - **Issue:** Once a user offloads an audiobook's audio file to save space, tapping the item only shows a dead-end alert ("File Offloaded") with an "OK" button and no way to restore or re-link the audio file while preserving progress.
  - **Fix:** Add a "Relink Audio File…" button to the alert and context menu that opens `.fileImporter` and re-attaches the selected audio file/folder to the existing `LibraryItem` (preserving its `id`, `currentPosition`, and history).

- [ ] **4.2 Fix Search to Include Nested Folder Items & Handle Folders/Offloaded Books**
  - **Location:** `ListenUp/Views/SearchView.swift` (lines 72–74, 134)
  - **Issue:**
    1. `SearchView` filters by `$0.parent == nil`, excluding any `.singleFile` or `.multiPart` books organized inside `.folder` items.
    2. Tapping a `.folder` result calls `player.loadAndPlay(item)` instead of navigating into the folder.
    3. Tapping an offloaded book in Search bypasses the offload check and attempts playback.
  - **Fix:** Filter search candidates by `$0.kind != .singleFile || $0.parent == nil || $0.parent?.kind == .folder` (all playable books + folders, excluding raw multi-part child tracks), navigate on folder tap, and check `item.isFileOffloaded` before playing.

- [ ] **4.3 Add Library Sorting & Completed Filter Controls**
  - **Location:** `ListenUp/Views/LibraryView.swift` (lines 29–34, 225–265)
  - **Issue:** Users cannot sort their library (e.g., by Recently Played, Title, Author, Duration, or Progress) and cannot filter strictly for Completed/Finished books.
  - **Fix:** Add a sort menu in the `LibraryView` header (`Last Played`, `Title`, `Author`, `Progress`, `Duration`) persisted via `@AppStorage`, and add a `.completed` case to `LibraryFilter`.

- [ ] **4.4 Enable Multi-Selection in File Importer**
  - **Location:** `ListenUp/Views/LibraryView.swift` (line 167)
  - **Issue:** `.fileImporter` sets `allowsMultipleSelection: false`, forcing users to import audiobooks one at a time or preventing them from selecting multiple loose MP3 tracks to form a book.
  - **Fix:** Set `allowsMultipleSelection: true` and support batch-importing multiple standalone books or grouping selected tracks.

- [ ] **4.5 Improve Chapters Sheet UX & Add User Bookmarks**
  - **Location:** `ListenUp/Views/FullPlayerView.swift` (line 400), `ListenUp/Views/ChaptersSheet.swift`
  - **Issue:** Tapping "Chapters" on a `.singleFile` book without embedded chapters opens an empty sheet. Additionally, learners using courses (like Pimsleur) or long audiobooks have no way to save custom timestamped bookmarks.
  - **Fix:** Show the chapter count badge on the Chapters button (or adapt its label when empty), and add a "Bookmarks" tab inside `ChaptersSheet` so users can save, rename, and jump to custom positions.

- [ ] **4.6 Enhance Watch Player with Digital Crown Scrubbing/Volume & Chapter List**
  - **Location:** `ListenUpWatch/Views/WatchNowPlayingView.swift`, `ListenUpWatch/Views/WatchLibraryView.swift`
  - **Issue:** `WatchNowPlayingView` lacks Digital Crown integration, chapter selection, and a visual "Now Playing" indicator in `WatchLibraryView`.
  - **Fix:** Add `.digitalCrownRotation` support for volume or fine scrubbing, add a chapter list sheet on Watch, and highlight the active book in `WatchLibraryView`.

- [ ] **4.7 Fix `LiquidGlassModifier` Interactive Press State**
  - **Location:** `ListenUp/Views/Components/LiquidGlass.swift` (lines 24, 59)
  - **Issue:** `@State private var isPressed = false` is declared and used for scale/shadow animations when `isInteractive == true`, but no gesture or button style ever updates `isPressed`.
  - **Fix:** Attach a non-blocking `DragGesture(minimumDistance: 0)` or move the press animation into a dedicated `ButtonStyle` so interactive glass cards respond to touch.

---

## Stage 5: Accessibility, Dynamic Type & Automated Testing

Ensuring ListenUp works seamlessly with VoiceOver, Dynamic Type, and has strong unit test coverage for core services.

- [ ] **5.1 Add Missing VoiceOver Accessibility Labels and Values**
  - **Location:** `ListenUp/Views/FullPlayerView.swift` (lines 118–124, 272–297, 319–370), `ListenUp/Views/MiniPlayerView.swift` (lines 136–170), `ListenUp/Views/Components/FloatingNavBar.swift` (lines 38–96), `ListenUp/Views/Components/LibraryRow.swift`
  - **Issue:** Icon-only transport buttons (play/pause, skip back 15s, skip forward 30s, dismiss chevron), the custom drag scrubber in `FullPlayerView`, and the custom `FloatingNavBar` tabs lack `.accessibilityLabel`, `.accessibilityValue`, and `.accessibilityAdjustableAction`.
  - **Fix:** Add explicit accessibility labels/traits to all icon buttons and implement `.accessibilityAdjustableAction` on the custom progress scrubber so VoiceOver users can scrub forward/backward.

- [ ] **5.2 Support Dynamic Type Across Custom Views**
  - **Location:** Throughout `ListenUp/Views/` (hardcoded `.system(size: ...)` font modifiers)
  - **Issue:** Most views use fixed point sizes (`.system(size: 14, weight: .semibold)`) and fixed frame heights, preventing text from scaling with the user's iOS/watchOS Dynamic Type accessibility settings.
  - **Fix:** Replace fixed `.system(size:)` declarations with semantic SwiftUI text styles (`.headline`, `.subheadline`, `.caption`, etc.) or scale custom sizes and container heights with `@ScaledMetric`.

- [ ] **5.3 Expand Unit Test Suite for Core Services**
  - **Location:** `Tests/ListenUpTests/ListenUpTests.swift`
  - **Issue:** Existing tests cover model computations, time formatting, and `ListeningStatsStore`, but lack tests for `FileImporterService`, `ListeningHistoryBackupService`, `AudioPlayerManager` virtual multi-part offset math, and `WidgetDataStore` round-tripping.
  - **Fix:** Add unit tests covering:
    1. Multi-part virtual timeline offset and chapter mapping math.
    2. `ListeningHistoryBackupService` archive creation, JSON decoding, and merge conflict resolution (newer vs. older `lastUpdated`, completion union, daily history max-seconds merge).
    3. `FileImporterService` persistence deduplication and folder hierarchy creation using an in-memory `ModelContainer`.
    4. Streak calculation across consecutive and gapped days in `ListeningStatsStore`.
