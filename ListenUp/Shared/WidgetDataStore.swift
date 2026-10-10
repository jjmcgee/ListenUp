import Foundation
import CoreGraphics
import ImageIO
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Thread-safe persistence bridge for sharing playback state, recent books, and stats
/// with iOS WidgetKit extensions via App Group `UserDefaults`.
public final class WidgetDataStore: @unchecked Sendable {
    
    public static let shared = WidgetDataStore()
    
    public static let appGroupID = "group.scot.mcg.ListenUp"
    public static let snapshotKey = "listenup_widget_data_snapshot_v1"
    
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "scot.mcg.ListenUp.WidgetDataStore", qos: .utility)
    
    private var lastReloadTimestamp: Date = .distantPast
    private let reloadThrottleInterval: TimeInterval = 10.0 // Avoid exhausting WidgetKit reload budgets
    
    public init(suiteName: String = appGroupID) {
        if let groupDefaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = .standard
        }
    }
    
    // MARK: - Snapshot Read & Write
    
    private var sharedFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("widget_data_snapshot.json")
    }
    
    public func loadSnapshot() -> WidgetDataSnapshot {
        if let data = userDefaults.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data) {
            return snapshot
        }
        if let fileURL = sharedFileURL,
           let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data) {
            return snapshot
        }
        return WidgetDataSnapshot()
    }
    
    // MARK: - In-Place Updates
    
    public func updatePlaybackSnapshot(_ playbackSnapshot: WidgetPlaybackSnapshot?, immediateReload: Bool = false) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var current = self.loadSnapshot()
            let wasPlaying = current.nowPlaying?.isPlaying ?? false
            let isPlaying = playbackSnapshot?.isPlaying ?? false
            current = WidgetDataSnapshot(
                nowPlaying: playbackSnapshot,
                recentBooks: current.recentBooks,
                stats: current.stats,
                lastUpdated: Date()
            )
            self.saveSnapshotSynchronously(current)
            if immediateReload || wasPlaying != isPlaying {
                self.reloadWidgetsImmediate()
            } else {
                self.reloadWidgetsThrottled()
            }
        }
    }
    
    public func updateRecentBooksList(_ recentBooks: [WidgetRecentBook]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var current = self.loadSnapshot()
            current = WidgetDataSnapshot(
                nowPlaying: current.nowPlaying,
                recentBooks: recentBooks,
                stats: current.stats,
                lastUpdated: Date()
            )
            self.saveSnapshotSynchronously(current)
            self.reloadWidgetsThrottled()
        }
    }
    
    public func updateStatsSnapshot(_ statsSnapshot: WidgetStatsSnapshot) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var current = self.loadSnapshot()
            current = WidgetDataSnapshot(
                nowPlaying: current.nowPlaying,
                recentBooks: current.recentBooks,
                stats: statsSnapshot,
                lastUpdated: Date()
            )
            self.saveSnapshotSynchronously(current)
            self.reloadWidgetsThrottled()
        }
    }
    
    // MARK: - WidgetKit Timeline Reloads
    
    /// Re-evaluates timelines for all widget families.
    public func reloadWidgetsImmediate() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func reloadWidgetsThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastReloadTimestamp) > reloadThrottleInterval else { return }
        lastReloadTimestamp = now
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func saveSnapshotSynchronously(_ snapshot: WidgetDataSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.snapshotKey)
            if let fileURL = sharedFileURL {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    // MARK: - Image Downsampling Utility
    
    /// Downsamples cover artwork data to a miniature thumbnail to maintain strict widget memory limits (<30MB).
    public func downsampleImage(data: Data, maxDimension: CGFloat) -> Data? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        
        let writeOptions = [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary
        CGImageDestinationAddImage(destination, downsampledImage, writeOptions)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return destinationData as Data
    }
}

#if !WIDGET_EXTENSION
// MARK: - Main App Synchronization Extensions

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
#endif
