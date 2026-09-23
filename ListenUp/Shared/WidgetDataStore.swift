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
    
    public func saveSnapshot(_ snapshot: WidgetDataSnapshot) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                self.userDefaults.set(data, forKey: Self.snapshotKey)
            } catch {
                print("[WidgetDataStore] Failed to encode snapshot: \(error.localizedDescription)")
            }
        }
    }
    
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
