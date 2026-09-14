import SwiftUI

@main
struct ListenUpWatchApp: App {
    
    @State private var syncManager = WatchSyncManager.shared
    @State private var libraryStore = WatchLibraryStore.shared
    @State private var localPlayer = WatchAudioPlayerManager.shared
    
    init() {
        setupWatchSyncWiring()
    }
    
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(syncManager)
                .environment(libraryStore)
                .environment(localPlayer)
        }
    }
    
    private func setupWatchSyncWiring() {
        // Wire audio file receipt into local library store
        syncManager.onAudioFileReceived = { [weak libraryStore] localURL, metadata in
            libraryStore?.handleAudioFileReceived(localURL: localURL, metadata: metadata)
        }
        
        // Wire incoming catalog delivery from iPhone
        syncManager.onLibraryCatalogReceived = { [weak libraryStore] summaries in
            libraryStore?.updateCatalog(summaries)
        }
        
        // Wire incoming progress updates from iPhone
        syncManager.onPlaybackSyncReceived = { [weak libraryStore] payload in
            libraryStore?.updatePlaybackState(
                bookID: payload.bookID,
                position: payload.position,
                isCompleted: payload.isCompleted
            )
        }
        
        // Wire local player progress updates back to iPhone
        localPlayer.onPositionUpdated = { [weak syncManager, weak libraryStore] bookID, position, isCompleted in
            libraryStore?.updatePlaybackState(bookID: bookID, position: position, isCompleted: isCompleted)
            let payload = PlaybackSyncPayload(
                bookID: bookID,
                position: position,
                isCompleted: isCompleted,
                lastUpdated: Date()
            )
            syncManager?.sendSyncPayload(payload)
        }
        
        // Request fresh catalog from phone on launch
        syncManager.requestLibraryCatalog()
    }
}
