import Foundation
import SwiftData

/// Unified hierarchical model representing an audio file, a multi-part continuous audiobook,
/// or a folder collection.
///
/// Strictly conforms to CloudKit constraints:
/// - All relationships are optional (`parent: LibraryItem?`, `children: [LibraryItem]?`).
/// - All stored properties have default initializers.
/// - Uses primitive raw values for enum storage (`kindRaw`).
@Model
public final class LibraryItem {
    
    // MARK: - Core Identifiers & Metadata
    
    public var id: UUID = UUID()
    public var title: String = ""
    public var author: String? = nil
    public var kindRaw: String = ItemKind.singleFile.rawValue
    
    /// Path relative to the application's `Documents/` directory sandbox.
    public var relativePath: String? = nil
    
    /// Total duration in seconds. For `.multiPart` or `.folder`, this is the cumulative sum of child tracks.
    public var totalDuration: Double = 0.0
    
    /// Current playback position in seconds along the virtual timeline.
    public var currentPosition: Double = 0.0
    
    /// Whether the user has marked or completed listening to this item.
    public var isCompleted: Bool = false
    
    /// User or file-order sort index within a parent collection.
    public var sortOrder: Int = 0
    
    /// Timestamp for multi-device sync conflict resolution ("latest lastUpdated wins").
    public var lastUpdated: Date = Date()
    
    /// Embedded cover art image data (stored externally to keep SQLite records lean).
    @Attribute(.externalStorage)
    public var artworkData: Data? = nil
    
    // MARK: - Hierarchical Relationships (CloudKit Compatible)
    
    public var parent: LibraryItem? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \LibraryItem.parent)
    public var children: [LibraryItem]? = []
    
    // MARK: - Initialization
    
    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        kind: ItemKind = .singleFile,
        relativePath: String? = nil,
        totalDuration: Double = 0.0,
        currentPosition: Double = 0.0,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        lastUpdated: Date = Date(),
        artworkData: Data? = nil,
        parent: LibraryItem? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kindRaw = kind.rawValue
        self.relativePath = relativePath
        self.totalDuration = totalDuration
        self.currentPosition = currentPosition
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.lastUpdated = lastUpdated
        self.artworkData = artworkData
        self.parent = parent
        self.children = []
    }
}

// MARK: - Computed Properties & Helpers

extension LibraryItem {
    
    /// Strongly-typed accessor for `kindRaw`.
    public var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .singleFile }
        set { kindRaw = newValue.rawValue }
    }
    
    /// Non-nil, sorted array of child items ordered by `sortOrder`, then `title`.
    public var sortedChildren: [LibraryItem] {
        guard let children = children else { return [] }
        return children.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    
    /// Returns the linear array of physical playable audio tracks.
    /// - For `.singleFile`: returns `[self]` if it has an audio path.
    /// - For `.multiPart`: returns sorted child tracks that are `.singleFile`.
    /// - For `.folder`: returns flattened playable tracks from all descendant sub-trees.
    public var playableTracks: [LibraryItem] {
        switch kind {
        case .singleFile:
            return relativePath != nil ? [self] : []
        case .multiPart:
            return sortedChildren.filter { $0.kind == .singleFile && $0.relativePath != nil }
        case .folder:
            return sortedChildren.flatMap { $0.playableTracks }
        }
    }
    
    /// Playback completion progress fraction clamped in `0.0 ... 1.0`.
    public var progress: Double {
        guard totalDuration > 0 else { return 0.0 }
        return min(max(currentPosition / totalDuration, 0.0), 1.0)
    }
    
    /// Formatted current position timestamp (e.g. "12:34" or "1:02:15").
    public var formattedCurrentPosition: String {
        TimeFormatting.formatTimestamp(currentPosition)
    }
    
    /// Formatted total duration (e.g. "1 hr 45 min" or "42 min").
    public var formattedTotalDuration: String {
        TimeFormatting.formatVerbalDuration(totalDuration)
    }
    
    /// Formatted remaining duration timestamp (e.g. "-15:20").
    public var formattedRemainingDuration: String {
        TimeFormatting.formatRemainingTimestamp(current: currentPosition, total: totalDuration)
    }
    
    /// Resolves the absolute file URL within the application sandbox documents directory.
    public func resolvedURL(
        relativeTo baseDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) -> URL? {
        guard let relativePath = relativePath, !relativePath.isEmpty else {
            return nil
        }
        let directURL = baseDirectory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }
        let audiobooksURL = baseDirectory.appendingPathComponent("Audiobooks").appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: audiobooksURL.path) {
            return audiobooksURL
        }
        return directURL
    }
    
    /// Recalculates `totalDuration` for `.multiPart` and `.folder` items based on child tracks.
    public func recalculateDurations() {
        if kind != .singleFile {
            let tracks = playableTracks
            totalDuration = tracks.reduce(0.0) { $0 + $1.totalDuration }
        }
    }
}

// MARK: - Virtual Multi-Part Segment Geometry

extension LibraryItem {
    
    /// Representation of a discrete audio file segment mapped onto a continuous virtual timeline.
    public struct Segment: Identifiable {
        public var id: UUID { track.id }
        public let track: LibraryItem
        public let trackIndex: Int
        public let startVirtualTime: Double
        public let duration: Double
        public var endVirtualTime: Double { startVirtualTime + duration }
    }
    
    /// Computes the continuous segment layout for this item's playable tracks.
    public var segments: [Segment] {
        let tracks = playableTracks
        var result: [Segment] = []
        result.reserveCapacity(tracks.count)
        
        var cumulativeTime: Double = 0.0
        for (index, track) in tracks.enumerated() {
            let dur = max(0.0, track.totalDuration)
            result.append(Segment(
                track: track,
                trackIndex: index,
                startVirtualTime: cumulativeTime,
                duration: dur
            ))
            cumulativeTime += dur
        }
        return result
    }
    
    /// Given a virtual timeline position `T`, locates the segment holding `T`
    /// and the local offset inside that segment's physical audio file.
    public func segment(at virtualPosition: Double) -> (segment: Segment, localOffset: Double)? {
        let segs = segments
        guard !segs.isEmpty else { return nil }
        
        let clampedT = min(max(virtualPosition, 0.0), totalDuration)
        
        // Find segment containing clampedT
        for seg in segs {
            if clampedT >= seg.startVirtualTime && clampedT < seg.endVirtualTime {
                return (seg, clampedT - seg.startVirtualTime)
            }
        }
        
        // Edge case: exactly at the end of the timeline
        if let last = segs.last {
            return (last, last.duration)
        }
        
        return nil
    }
    
    /// Computes virtual timeline position given a track index and local physical file offset.
    public func virtualPosition(trackIndex: Int, localOffset: Double) -> Double {
        let segs = segments
        guard trackIndex >= 0 && trackIndex < segs.count else {
            return localOffset
        }
        let seg = segs[trackIndex]
        return min(max(seg.startVirtualTime + localOffset, 0.0), totalDuration)
    }
}
