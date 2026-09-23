import SwiftUI
import SwiftData

/// Main application entry point for ListenUp.
@main
struct ListenUpApp: App {
    
    // Shared SwiftData model container
    let container = AppDatabase.shared.container
    
    // Playback and sync managers
    private let player = AudioPlayerManager.shared
    private let watchSync = WatchSyncManager.shared
    private let navigationCoordinator = NavigationCoordinator.shared
    
    // User interface theme setting
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    @MainActor
    init() {
        setupSyncWiring()
        setupDarwinNotificationObserver()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(player)
                .environment(watchSync)
                .environment(navigationCoordinator)
                .modelContainer(container)
                .preferredColorScheme(appTheme.colorScheme)
                .onOpenURL { url in
                    navigationCoordinator.handleURL(url, in: container.mainContext, player: player)
                }
        }
    }
    
    @MainActor
    private func setupSyncWiring() {
        let context = container.mainContext
        
        // 1. Wire audio engine position updates to WatchSync and Widgets
        player.onPositionUpdated = { [weak watchSync, weak player] item, _ in
            try? context.save()
            watchSync?.syncPlaybackState(for: item)
            broadcastPlaybackStateToWatch()
            if let p = player {
                WidgetDataStore.shared.syncPlayback(
                    item: item,
                    isPlaying: p.isPlaying,
                    currentTime: p.currentTime,
                    totalDuration: p.totalDuration
                )
            }
        }
        
        // Wire playback state changes (play, pause, next track) to Widgets
        NotificationCenter.default.addObserver(
            forName: AudioPlayerManager.playbackStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak player] _ in
            Task { @MainActor in
                guard let player = player else { return }
                WidgetDataStore.shared.syncPlayback(
                    item: player.currentItem,
                    isPlaying: player.isPlaying,
                    currentTime: player.currentTime,
                    totalDuration: player.totalDuration
                )
            }
        }
        
        // 2. Wire incoming watchOS sync updates to SwiftData
        watchSync.onPlaybackSyncReceived = { [weak player] payload in
            let itemID = payload.bookID
            let descriptor = FetchDescriptor<LibraryItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            
            if let items = try? context.fetch(descriptor), let item = items.first {
                let didApply = WatchSyncManager.applySyncUpdate(payload: payload, to: item)
                if didApply {
                    try? context.save()
                    // If this is the actively loaded item in the player, sync its timeline
                    if player?.currentItem?.id == item.id {
                        player?.seek(to: item.currentPosition)
                    }
                }
            }
        }
        
        // 3. Wire Remote Commands from Apple Watch (Control iPhone playback)
        watchSync.onRemoteCommandReceived = { [weak player] command in
            guard let player = player else { return }
            
            switch command.type {
            case .play:
                player.resume()
            case .pause:
                player.pause()
            case .togglePlayPause:
                player.togglePlayPause()
            case .skipForward:
                player.skipForward(by: command.value ?? 30.0)
            case .skipBackward:
                player.skipBackward(by: command.value ?? 15.0)
            case .seek:
                if let target = command.value {
                    player.seek(to: target)
                }
            case .setPlaybackRate:
                if let rate = command.value {
                    player.setPlaybackRate(Float(rate))
                }
            case .nextChapter:
                player.skipToNextChapter()
            case .previousChapter:
                player.skipToPreviousChapter()
            }
            
            broadcastPlaybackStateToWatch()
        }
        
        // 4. Wire Library Catalog Requests from Apple Watch
        watchSync.onLibraryCatalogRequested = {
            broadcastLibraryCatalogToWatch()
        }
        
        // 5. Wire Download Requests from Apple Watch
        watchSync.onDownloadRequestReceived = { [weak watchSync] bookID in
            let descriptor = FetchDescriptor<LibraryItem>(
                predicate: #Predicate { $0.id == bookID }
            )
            if let items = try? context.fetch(descriptor), let item = items.first {
                watchSync?.transferBookToWatch(item: item)
            }
        }
        
        // 6. Broadcast initial state and catalog on launch
        broadcastLibraryCatalogToWatch()
        broadcastPlaybackStateToWatch()
    }
    
    @MainActor
    private func broadcastPlaybackStateToWatch() {
        let state = WatchRemotePlaybackState(
            bookID: player.currentItem?.id,
            title: player.currentItem?.title ?? "",
            author: player.currentItem?.author,
            chapterTitle: player.currentChapter?.title,
            currentTime: player.currentTime,
            totalDuration: player.totalDuration,
            isPlaying: player.isPlaying,
            playbackRate: player.playbackRate,
            isCompleted: player.currentItem?.isCompleted ?? false,
            lastUpdated: Date()
        )
        watchSync.broadcastRemotePlaybackState(state)
    }
    
    @MainActor
    private func broadcastLibraryCatalogToWatch() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.parent == nil && !$0.isDeletedFromLibrary }
        )
        
        guard let items = try? context.fetch(descriptor) else { return }
        
        let summaries: [WatchLibraryItemSummary] = items.map { item in
            WatchLibraryItemSummary(
                id: item.id,
                title: item.title,
                author: item.author,
                kindRaw: item.kindRaw,
                totalDuration: item.totalDuration,
                currentPosition: item.currentPosition,
                isCompleted: item.isCompleted,
                lastUpdated: item.lastUpdated,
                trackCount: item.playableTracks.count
            )
        }
        
        watchSync.broadcastLibraryCatalog(summaries)
        
        // Sync recent books and listening stats to WidgetDataStore
        WidgetDataStore.shared.syncRecentBooks(items: items)
        ListeningStatsStore.shared.syncToWidgets(items: items)
        
        // Restore last in-progress audiobook into player & sync to widgets if player has no current item
        if player.currentItem == nil {
            let activeOrRecent = items
                .filter { !$0.isCompleted }
                .sorted { $0.lastUpdated > $1.lastUpdated }
                .first ?? items.first
            
            if let item = activeOrRecent {
                player.prepare(item: item)
                WidgetDataStore.shared.syncPlayback(
                    item: item,
                    isPlaying: false,
                    currentTime: item.currentPosition,
                    totalDuration: item.totalDuration
                )
            }
        }
    }
    
    private func setupDarwinNotificationObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = "scot.mcg.ListenUp.togglePlayback" as CFString
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    AudioPlayerManager.shared.togglePlayPause()
                }
            },
            name,
            nil,
            .deliverImmediately
        )
    }
}
