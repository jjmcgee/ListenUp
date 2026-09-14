import Foundation
import SwiftData

/// Download and storage status for an audiobook on Apple Watch.
public enum BookWatchStatus: Equatable, Sendable {
    case onPhoneOnly
    case downloading(progress: Double)
    case downloaded(trackCount: Int)
    
    public var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }
    
    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Observable store on watchOS managing the library catalog, tracking downloaded audio tracks,
/// initiating downloads from iPhone, and managing local watch storage.
@Observable
@MainActor
public final class WatchLibraryStore {
    
    public static let shared = WatchLibraryStore()
    
    /// Cached catalog of audiobooks synced from iPhone.
    public private(set) var books: [WatchLibraryItemSummary] = []
    
    /// IDs of books that are completely downloaded on this Apple Watch.
    public private(set) var downloadedBookIDs: Set<UUID> = []
    
    /// Maps book ID to in-flight download progress fraction (0.0 ... 1.0).
    public private(set) var downloadProgress: [UUID: Double] = [:]
    
    /// Maps book ID to locally downloaded physical audio file URLs.
    public private(set) var localAudioURLs: [UUID: [URL]] = [:]
    
    public init() {
        refreshDownloadedFiles()
    }
    
    // MARK: - Status Queries
    
    public func status(for bookID: UUID) -> BookWatchStatus {
        if let progress = downloadProgress[bookID] {
            return .downloading(progress: progress)
        }
        if downloadedBookIDs.contains(bookID), let urls = localAudioURLs[bookID], !urls.isEmpty {
            return .downloaded(trackCount: urls.count)
        }
        return .onPhoneOnly
    }
    
    public func localURLs(for bookID: UUID) -> [URL] {
        return localAudioURLs[bookID] ?? []
    }
    
    // MARK: - Catalog Synchronization
    
    /// Updates the local catalog with summaries received from iPhone.
    public func updateCatalog(_ items: [WatchLibraryItemSummary]) {
        self.books = items
        refreshDownloadedFiles()
    }
    
    /// Updates playback position and completion for a book in the catalog.
    public func updatePlaybackState(bookID: UUID, position: Double, isCompleted: Bool) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let current = books[index]
        let updated = WatchLibraryItemSummary(
            id: current.id,
            title: current.title,
            author: current.author,
            kindRaw: current.kindRaw,
            totalDuration: current.totalDuration,
            currentPosition: position,
            isCompleted: isCompleted,
            lastUpdated: Date(),
            trackCount: current.trackCount
        )
        books[index] = updated
    }
    
    // MARK: - File Management & Download Status
    
    /// Scans the watch app's `Documents/Audiobooks/` sandbox to detect downloaded tracks.
    public func refreshDownloadedFiles() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let audiobooksDir = documentsURL.appendingPathComponent("Audiobooks", isDirectory: true)
        guard fileManager.fileExists(atPath: audiobooksDir.path) else { return }
        
        var newDownloadedIDs = Set<UUID>()
        var newLocalURLs: [UUID: [URL]] = [:]
        
        guard let bookDirectories = try? fileManager.contentsOfDirectory(at: audiobooksDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for dir in bookDirectories {
            guard let bookID = UUID(uuidString: dir.lastPathComponent) else { continue }
            
            if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let audioFiles = files.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "m4b" || ext == "m4a" || ext == "mp3" || ext == "aac" || ext == "wav"
                }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                
                if !audioFiles.isEmpty {
                    newLocalURLs[bookID] = audioFiles
                    
                    // If we know the expected track count from the catalog, check completeness
                    if let summary = books.first(where: { $0.id == bookID }) {
                        if audioFiles.count >= summary.trackCount {
                            newDownloadedIDs.insert(bookID)
                            downloadProgress.removeValue(forKey: bookID)
                        } else {
                            let prog = Double(audioFiles.count) / Double(max(summary.trackCount, 1))
                            downloadProgress[bookID] = prog
                        }
                    } else {
                        // Fallback: at least one file exists
                        newDownloadedIDs.insert(bookID)
                        downloadProgress.removeValue(forKey: bookID)
                    }
                }
            }
        }
        
        self.downloadedBookIDs = newDownloadedIDs
        self.localAudioURLs = newLocalURLs
    }
    
    /// Called when an incoming audio file has been delivered to Apple Watch.
    public func handleAudioFileReceived(localURL: URL, metadata: ReceivedAudioMetadata) {
        guard let bookID = metadata.bookID else { return }
        
        var urls = localAudioURLs[bookID] ?? []
        if !urls.contains(where: { $0.lastPathComponent == localURL.lastPathComponent }) {
            urls.append(localURL)
            urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            localAudioURLs[bookID] = urls
        }
        
        let totalParts = metadata.totalParts ?? 1
        let receivedParts = urls.count
        
        if receivedParts >= totalParts {
            downloadProgress.removeValue(forKey: bookID)
            downloadedBookIDs.insert(bookID)
        } else {
            downloadProgress[bookID] = Double(receivedParts) / Double(totalParts)
        }
    }
    
    // MARK: - User Actions (Download & Delete)
    
    /// Initiates a download request to the iPhone.
    public func requestDownload(for bookID: UUID) {
        downloadProgress[bookID] = 0.05
        WatchSyncManager.shared.requestBookDownload(bookID: bookID)
    }
    
    /// Deletes all downloaded audio files for a book from Apple Watch to free disk space.
    public func deleteDownloadedBook(bookID: UUID) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let bookDir = documentsURL.appendingPathComponent("Audiobooks").appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: bookDir)
        
        downloadedBookIDs.remove(bookID)
        downloadProgress.removeValue(forKey: bookID)
        localAudioURLs.removeValue(forKey: bookID)
    }
    
    // MARK: - Storage Information
    
    /// Total bytes consumed by downloaded audiobooks in the watch sandbox.
    public func totalStorageUsedBytes() -> Int64 {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        
        let audiobooksDir = documentsURL.appendingPathComponent("Audiobooks", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: audiobooksDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
    
    /// Formatted string representing watch storage used (e.g. "124 MB").
    public func formattedStorageUsed() -> String {
        let bytes = totalStorageUsedBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
