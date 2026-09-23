import SwiftUI
import SwiftData

/// Centralized coordinator for app tab selection, sheet presentations, and deep linking from widgets.
@Observable
@MainActor
public final class NavigationCoordinator {
    
    public static let shared = NavigationCoordinator()
    
    public var selectedTab: NavTab = .library
    public var isShowingFullPlayer: Bool = false
    
    public init() {}
    
    /// Handles incoming deep links from WidgetKit (e.g., `listenup://play?id=...`, `listenup://stats`).
    public func handleURL(_ url: URL, in context: ModelContext, player: AudioPlayerManager) {
        guard url.scheme?.lowercased() == "listenup" else { return }
        
        let host = url.host?.lowercased() ?? ""
        
        switch host {
        case "stats", "profile":
            selectedTab = .profile
            
        case "nowplaying", "player":
            if player.currentItem == nil {
                let descriptor = FetchDescriptor<LibraryItem>(
                    predicate: #Predicate { $0.parent == nil && !$0.isDeletedFromLibrary },
                    sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
                )
                if let items = try? context.fetch(descriptor), let item = items.first {
                    player.prepare(item: item)
                }
            }
            if player.currentItem != nil {
                isShowingFullPlayer = true
            }
            
        case "play", "book":
            // Extract UUID from query parameter or path
            let idString: String?
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItem = components.queryItems?.first(where: { $0.name == "id" })?.value {
                idString = queryItem
            } else {
                idString = url.pathComponents.filter({ $0 != "/" }).last
            }
            
            if let idString = idString, let itemID = UUID(uuidString: idString) {
                let descriptor = FetchDescriptor<LibraryItem>(
                    predicate: #Predicate { $0.id == itemID }
                )
                if let items = try? context.fetch(descriptor), let item = items.first {
                    player.play(item: item)
                    isShowingFullPlayer = true
                }
            }
            
        default:
            break
        }
    }
}

// MARK: - WidgetDataStore Main App Synchronization

extension WidgetDataStore {
    
    /// Syncs playback state from SwiftData `LibraryItem` and `AudioPlayerManager` to the widget cache.
    public func syncPlayback(
        item: LibraryItem?,
        isPlaying: Bool,
        currentTime: Double,
        totalDuration: Double
    ) {
        if let item = item {
            let thumb = item.artworkData.flatMap { downsampleImage(data: $0, maxDimension: 160) }
            let snapshot = WidgetPlaybackSnapshot(
                bookID: item.id,
                title: item.title,
                author: item.author ?? "Unknown Author",
                currentTime: currentTime,
                totalDuration: totalDuration > 0 ? totalDuration : item.totalDuration,
                progress: totalDuration > 0 ? currentTime / totalDuration : item.progress,
                isPlaying: isPlaying,
                artworkData: thumb,
                lastUpdated: Date()
            )
            updatePlaybackSnapshot(snapshot, immediateReload: true)
        } else {
            // Keep existing book details, only set isPlaying = false
            let current = loadSnapshot()
            if let existing = current.nowPlaying {
                let updated = WidgetPlaybackSnapshot(
                    bookID: existing.bookID,
                    title: existing.title,
                    author: existing.author,
                    currentTime: existing.currentTime,
                    totalDuration: existing.totalDuration,
                    progress: existing.progress,
                    isPlaying: false,
                    artworkData: existing.artworkData,
                    lastUpdated: Date()
                )
                updatePlaybackSnapshot(updated, immediateReload: true)
            }
        }
    }
    
    /// Syncs recent books from SwiftData `LibraryItem` to the widget cache.
    public func syncRecentBooks(items: [LibraryItem]) {
        let topRecent = items
            .filter { $0.parent == nil && !$0.isDeletedFromLibrary }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .prefix(4)
            .map { item in
                let thumb = item.artworkData.flatMap { downsampleImage(data: $0, maxDimension: 120) }
                return WidgetRecentBook(
                    id: item.id,
                    title: item.title,
                    author: item.author ?? "Unknown Author",
                    progress: item.progress,
                    totalDuration: item.totalDuration,
                    artworkData: thumb,
                    lastUpdated: item.lastUpdated
                )
            }
        updateRecentBooksList(Array(topRecent))
    }
    
    /// Syncs aggregated stats from `ListeningStatsStore` to the widget cache.
    public func syncStats(
        todaySeconds: Double,
        dailyGoalMinutes: Int,
        monthly: ListeningStatsStore.MonthlyComparison,
        total: ListeningStatsStore.TotalListeningBreakdown,
        streakDays: Int = 1
    ) {
        let todaySecs = Int(todaySeconds)
        let totalMins = todaySecs / 60
        let todayHours = totalMins / 60
        let todayMinutes = totalMins % 60
        
        let todayFormatted: String
        if todayHours > 0 {
            todayFormatted = "\(todayHours)h \(todayMinutes)m"
        } else {
            todayFormatted = "\(todayMinutes)m"
        }
        
        let goal = max(1, dailyGoalMinutes)
        let goalFraction = min(1.0, max(0.0, Double(totalMins) / Double(goal)))
        let remainingMinutes = max(0, goal - totalMins)
        
        let statsSnapshot = WidgetStatsSnapshot(
            todaySeconds: todaySeconds,
            todayHours: todayHours,
            todayMinutes: todayMinutes,
            todayFormatted: todayFormatted,
            goalMinutes: goal,
            goalProgressFraction: goalFraction,
            goalPercentageText: "\(Int(goalFraction * 100))%",
            isGoalAccomplished: goalFraction >= 1.0,
            remainingMinutes: remainingMinutes,
            currentMonthName: monthly.currentMonthName,
            currentMonthHours: monthly.currentMonthHours,
            previousMonthName: monthly.previousMonthName,
            previousMonthHours: monthly.previousMonthHours,
            monthDeltaHours: monthly.hoursDelta,
            monthPercentageChange: monthly.percentageChange,
            totalSummaryFormatted: total.formattedSummary,
            totalHours: total.totalHours,
            streakDays: streakDays,
            lastUpdated: Date()
        )
        updateStatsSnapshot(statsSnapshot)
    }
}
