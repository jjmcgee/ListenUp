import SwiftUI
import SwiftData

/// Main application entry point for ListenUp.
@main
struct ListenUpApp: App {
    
    // Shared SwiftData model container
    let container: ModelContainer
    
    // Playback and sync managers
    @State private var player = AudioPlayerManager()
    @State private var watchSync = WatchSyncManager.shared
    
    init() {
        do {
            let schema = Schema([
                LibraryItem.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            self.container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(player)
                .modelContainer(container)
                .task {
                    setupSyncWiring()
                }
        }
    }
    
    @MainActor
    private func setupSyncWiring() {
        let context = container.mainContext
        
        // Wire audio engine position updates to WatchSync
        player.onPositionUpdated = { [weak watchSync] item, _ in
            try? context.save()
            watchSync?.syncPlaybackState(for: item)
        }
        
        // Wire incoming watchOS sync updates to SwiftData
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
    }
}
