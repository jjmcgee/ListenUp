import Foundation
import AppIntents

#if !WIDGET_EXTENSION
import SwiftData
#endif

/// App Intent for toggling playback directly from interactive widgets.
public struct TogglePlaybackIntent: AppIntent, AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Toggle Playback"
    public static let description = IntentDescription("Toggles playback of the current audiobook in ListenUp.")
    
    public static let openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run {
            let player = AudioPlayerManager.shared
            if player.currentItem != nil {
                player.togglePlayPause()
            } else {
                // If no player is actively configured, find the target book to play
                let store = WidgetDataStore.shared
                let snapshot = store.loadSnapshot()
                let context = AppDatabase.shared.mainContext
                
                var targetItem: LibraryItem? = nil
                if let bookID = snapshot.nowPlaying?.bookID {
                    let descriptor = FetchDescriptor<LibraryItem>(
                        predicate: #Predicate { $0.id == bookID }
                    )
                    targetItem = try? context.fetch(descriptor).first
                }
                
                if targetItem == nil, let recentID = snapshot.recentBooks.first?.id {
                    let descriptor = FetchDescriptor<LibraryItem>(
                        predicate: #Predicate { $0.id == recentID }
                    )
                    targetItem = try? context.fetch(descriptor).first
                }
                
                if targetItem == nil {
                    let descriptor = FetchDescriptor<LibraryItem>(
                        predicate: #Predicate { $0.parent == nil && !$0.isDeletedFromLibrary },
                        sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
                    )
                    targetItem = try? context.fetch(descriptor).first
                }
                
                if let item = targetItem {
                    player.play(item: item)
                }
            }
        }
        #endif
        
        // Optimistically update shared snapshot for immediate UI feedback in widget
        let store = WidgetDataStore.shared
        var snapshot = store.loadSnapshot()
        if let current = snapshot.nowPlaying {
            let updated = WidgetPlaybackSnapshot(
                bookID: current.bookID,
                title: current.title,
                author: current.author,
                currentTime: current.currentTime,
                totalDuration: current.totalDuration,
                progress: current.progress,
                isPlaying: !current.isPlaying,
                artworkData: current.artworkData,
                lastUpdated: Date()
            )
            snapshot = WidgetDataSnapshot(
                nowPlaying: updated,
                recentBooks: snapshot.recentBooks,
                stats: snapshot.stats,
                lastUpdated: Date()
            )
            store.saveSnapshotSynchronously(snapshot)
            store.reloadWidgetsImmediate()
        }
        
        return .result()
    }
}
