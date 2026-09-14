import Foundation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Playback Sync Payload

/// Lightweight playback state payload exchanged between iOS and watchOS.
public struct PlaybackSyncPayload: Codable, Sendable {
    public let bookID: UUID
    public let position: Double
    public let isCompleted: Bool
    public let lastUpdated: Date
    
    public init(bookID: UUID, position: Double, isCompleted: Bool, lastUpdated: Date) {
        self.bookID = bookID
        self.position = position
        self.isCompleted = isCompleted
        self.lastUpdated = lastUpdated
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            "msgType": "playbackSync",
            "bookID": bookID.uuidString,
            "position": position,
            "isCompleted": isCompleted,
            "lastUpdated": lastUpdated.timeIntervalSince1970
        ]
    }
    
    public static func from(dictionary: [String: Any]) -> PlaybackSyncPayload? {
        guard (dictionary["msgType"] as? String == "playbackSync" || dictionary["msgType"] == nil),
              let idString = dictionary["bookID"] as? String,
              let uuid = UUID(uuidString: idString),
              let position = dictionary["position"] as? Double,
              let isCompleted = dictionary["isCompleted"] as? Bool,
              let timeInterval = dictionary["lastUpdated"] as? Double else {
            return nil
        }
        return PlaybackSyncPayload(
            bookID: uuid,
            position: position,
            isCompleted: isCompleted,
            lastUpdated: Date(timeIntervalSince1970: timeInterval)
        )
    }
}

// MARK: - Remote Control Commands

/// Discrete playback commands dispatched from Apple Watch to control iPhone playback.
public enum WatchRemoteCommandType: String, Codable, Sendable {
    case play
    case pause
    case togglePlayPause
    case skipForward
    case skipBackward
    case seek
    case setPlaybackRate
    case nextChapter
    case previousChapter
}

/// Strongly-typed command envelope sent across WatchConnectivity.
public struct WatchRemoteCommand: Sendable {
    public let type: WatchRemoteCommandType
    public let value: Double?
    
    public init(type: WatchRemoteCommandType, value: Double? = nil) {
        self.type = type
        self.value = value
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "msgType": "remoteCommand",
            "command": type.rawValue
        ]
        if let value = value {
            dict["value"] = value
        }
        return dict
    }
    
    public static func from(dictionary: [String: Any]) -> WatchRemoteCommand? {
        guard dictionary["msgType"] as? String == "remoteCommand",
              let raw = dictionary["command"] as? String,
              let type = WatchRemoteCommandType(rawValue: raw) else {
            return nil
        }
        let value = dictionary["value"] as? Double
        return WatchRemoteCommand(type: type, value: value)
    }
}

// MARK: - Remote Playback State

/// Snapshot of the iPhone's active playback status delivered to Apple Watch for Now Playing display.
public struct WatchRemotePlaybackState: Sendable {
    public let bookID: UUID?
    public let title: String
    public let author: String?
    public let chapterTitle: String?
    public let currentTime: Double
    public let totalDuration: Double
    public let isPlaying: Bool
    public let playbackRate: Float
    public let isCompleted: Bool
    public let lastUpdated: Date
    public let artworkThumbnailData: Data?
    
    public init(
        bookID: UUID?,
        title: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        currentTime: Double,
        totalDuration: Double,
        isPlaying: Bool,
        playbackRate: Float = 1.0,
        isCompleted: Bool = false,
        lastUpdated: Date = Date(),
        artworkThumbnailData: Data? = nil
    ) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.isCompleted = isCompleted
        self.lastUpdated = lastUpdated
        self.artworkThumbnailData = artworkThumbnailData
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "msgType": "remotePlaybackState",
            "title": title,
            "currentTime": currentTime,
            "totalDuration": totalDuration,
            "isPlaying": isPlaying,
            "playbackRate": Double(playbackRate),
            "isCompleted": isCompleted,
            "lastUpdated": lastUpdated.timeIntervalSince1970
        ]
        if let bookID = bookID { dict["bookID"] = bookID.uuidString }
        if let author = author { dict["author"] = author }
        if let chapterTitle = chapterTitle { dict["chapterTitle"] = chapterTitle }
        if let artworkThumbnailData = artworkThumbnailData { dict["artworkThumbnailData"] = artworkThumbnailData }
        return dict
    }
    
    public static func from(dictionary: [String: Any]) -> WatchRemotePlaybackState? {
        guard dictionary["msgType"] as? String == "remotePlaybackState",
              let title = dictionary["title"] as? String,
              let currentTime = dictionary["currentTime"] as? Double,
              let totalDuration = dictionary["totalDuration"] as? Double,
              let isPlaying = dictionary["isPlaying"] as? Bool,
              let rateVal = dictionary["playbackRate"] as? Double,
              let isCompleted = dictionary["isCompleted"] as? Bool,
              let timeInterval = dictionary["lastUpdated"] as? Double else {
            return nil
        }
        
        let bookID: UUID? = (dictionary["bookID"] as? String).flatMap(UUID.init(uuidString:))
        let author = dictionary["author"] as? String
        let chapterTitle = dictionary["chapterTitle"] as? String
        let artworkData = dictionary["artworkThumbnailData"] as? Data
        
        return WatchRemotePlaybackState(
            bookID: bookID,
            title: title,
            author: author,
            chapterTitle: chapterTitle,
            currentTime: currentTime,
            totalDuration: totalDuration,
            isPlaying: isPlaying,
            playbackRate: Float(rateVal),
            isCompleted: isCompleted,
            lastUpdated: Date(timeIntervalSince1970: timeInterval),
            artworkThumbnailData: artworkData
        )
    }
}

// MARK: - Library Summary Item

/// Lightweight catalog item representing an audiobook available on iPhone.
public struct WatchLibraryItemSummary: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let author: String?
    public let kindRaw: String
    public let totalDuration: Double
    public let currentPosition: Double
    public let isCompleted: Bool
    public let lastUpdated: Date
    public let trackCount: Int
    
    public init(
        id: UUID,
        title: String,
        author: String?,
        kindRaw: String,
        totalDuration: Double,
        currentPosition: Double,
        isCompleted: Bool,
        lastUpdated: Date,
        trackCount: Int
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kindRaw = kindRaw
        self.totalDuration = totalDuration
        self.currentPosition = currentPosition
        self.isCompleted = isCompleted
        self.lastUpdated = lastUpdated
        self.trackCount = trackCount
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "kindRaw": kindRaw,
            "totalDuration": totalDuration,
            "currentPosition": currentPosition,
            "isCompleted": isCompleted,
            "lastUpdated": lastUpdated.timeIntervalSince1970,
            "trackCount": trackCount
        ]
        if let author = author { dict["author"] = author }
        return dict
    }
    
    public static func from(dictionary: [String: Any]) -> WatchLibraryItemSummary? {
        guard let idStr = dictionary["id"] as? String,
              let id = UUID(uuidString: idStr),
              let title = dictionary["title"] as? String,
              let kindRaw = dictionary["kindRaw"] as? String,
              let totalDuration = dictionary["totalDuration"] as? Double,
              let currentPosition = dictionary["currentPosition"] as? Double,
              let isCompleted = dictionary["isCompleted"] as? Bool,
              let timeInterval = dictionary["lastUpdated"] as? Double,
              let trackCount = dictionary["trackCount"] as? Int else {
            return nil
        }
        let author = dictionary["author"] as? String
        return WatchLibraryItemSummary(
            id: id,
            title: title,
            author: author,
            kindRaw: kindRaw,
            totalDuration: totalDuration,
            currentPosition: currentPosition,
            isCompleted: isCompleted,
            lastUpdated: Date(timeIntervalSince1970: timeInterval),
            trackCount: trackCount
        )
    }
}

// MARK: - Audio Metadata & Transfer Tracking

/// Strongly-typed, sendable metadata delivered alongside transferred audio files.
public struct ReceivedAudioMetadata: Sendable {
    public let bookID: UUID?
    public let trackID: UUID?
    public let partIndex: Int?
    public let totalParts: Int?
    public let title: String?
    public let totalDuration: Double?
    public let fileName: String?
    
    public init(from dictionary: [String: Any]) {
        if let idStr = dictionary["bookID"] as? String {
            self.bookID = UUID(uuidString: idStr)
        } else {
            self.bookID = nil
        }
        if let trackIdStr = dictionary["trackID"] as? String {
            self.trackID = UUID(uuidString: trackIdStr)
        } else {
            self.trackID = nil
        }
        self.partIndex = dictionary["partIndex"] as? Int
        self.totalParts = dictionary["totalParts"] as? Int
        self.title = dictionary["title"] as? String
        self.totalDuration = dictionary["totalDuration"] as? Double
        self.fileName = dictionary["fileName"] as? String
    }
}

/// Information regarding an in-flight file transfer to watchOS.
public struct WatchFileTransferStatus: Identifiable, Sendable {
    public var id: String
    public var bookID: UUID
    public var partIndex: Int
    public var totalParts: Int
    public var title: String
    public var fractionCompleted: Double
    public var isTransferring: Bool
    
    public init(
        id: String = UUID().uuidString,
        bookID: UUID,
        partIndex: Int,
        totalParts: Int = 1,
        title: String,
        fractionCompleted: Double,
        isTransferring: Bool
    ) {
        self.id = id
        self.bookID = bookID
        self.partIndex = partIndex
        self.totalParts = totalParts
        self.title = title
        self.fractionCompleted = fractionCompleted
        self.isTransferring = isTransferring
    }
}

// MARK: - WatchSyncManager

/// Multi-device sync manager coordinating lightweight playback state, remote control commands,
/// library catalog synchronization, and offline audio file transfers via WatchConnectivity (`WCSession`).
///
/// Invariant: State conflict resolution follows "latest `lastUpdated` timestamp wins".
@Observable
@MainActor
public final class WatchSyncManager: NSObject {
    
    public static let shared = WatchSyncManager()
    
    /// Whether WatchConnectivity is supported on the current platform.
    public var isSupported: Bool {
        #if canImport(WatchConnectivity)
        return WCSession.isSupported()
        #else
        return false
        #endif
    }
    
    /// Whether the paired device is currently reachable for real-time messaging.
    public private(set) var isReachable: Bool = false
    
    /// Latest remote playback state received from the paired device (for watchOS player display).
    public private(set) var remotePlaybackState: WatchRemotePlaybackState?
    
    /// Synced library catalog from the phone (available on Apple Watch).
    public private(set) var librarySummaries: [WatchLibraryItemSummary] = []
    
    /// Tracks progress for active outgoing file transfers to Apple Watch.
    public private(set) var activeTransfers: [WatchFileTransferStatus] = []
    
    // MARK: - Callbacks
    
    /// Callback triggered when an incoming progress update is received.
    public var onPlaybackSyncReceived: ((PlaybackSyncPayload) -> Void)?
    
    /// Callback triggered when a remote control command is received from watchOS (handled by iOS audio player).
    public var onRemoteCommandReceived: ((WatchRemoteCommand) -> Void)?
    
    /// Callback triggered when remote playback state is updated.
    public var onRemotePlaybackStateReceived: ((WatchRemotePlaybackState) -> Void)?
    
    /// Callback triggered when Apple Watch requests the full library catalog from iOS.
    public var onLibraryCatalogRequested: (() -> Void)?
    
    /// Callback triggered when the library catalog arrives from iOS.
    public var onLibraryCatalogReceived: (([WatchLibraryItemSummary]) -> Void)?
    
    /// Callback triggered when Apple Watch requests a book to be downloaded from iOS.
    public var onDownloadRequestReceived: ((UUID) -> Void)?
    
    /// Callback triggered when an audio file has been delivered to this device.
    public var onAudioFileReceived: ((_ localURL: URL, _ metadata: ReceivedAudioMetadata) -> Void)?
    
    #if canImport(WatchConnectivity)
    private var session: WCSession?
    private var progressObservations: [NSKeyValueObservation] = []
    #endif
    
    public override init() {
        super.init()
        setupWatchSession()
    }
    
    private func setupWatchSession() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        #endif
    }
    
    // MARK: - Remote Control Commands (Watch -> Phone)
    
    /// Dispatches a remote playback command from Apple Watch to the iPhone.
    public func sendRemoteCommand(_ command: WatchRemoteCommand) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let dict = command.toDictionary()
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                print("[WatchSyncManager] Failed to send remote command: \(error.localizedDescription)")
            }
        }
        #endif
    }
    
    // MARK: - Remote Playback State Broadcast (Phone -> Watch)
    
    /// Broadcasts current iPhone playback state to Apple Watch for Now Playing UI.
    public func broadcastRemotePlaybackState(_ state: WatchRemotePlaybackState) {
        self.remotePlaybackState = state
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let dict = state.toDictionary()
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { [weak self] _ in
                // Fallback to application context if message dropped
                try? self?.session?.updateApplicationContext(dict)
            }
        } else {
            try? session.updateApplicationContext(dict)
        }
        #endif
    }
    
    // MARK: - Library Catalog Sync (Phone -> Watch)
    
    /// Broadcasts the current library catalog summaries to Apple Watch.
    public func broadcastLibraryCatalog(_ items: [WatchLibraryItemSummary]) {
        self.librarySummaries = items
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let dictList = items.map { $0.toDictionary() }
        let payload: [String: Any] = [
            "msgType": "libraryCatalog",
            "items": dictList
        ]
        
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                try? self?.session?.updateApplicationContext(payload)
            }
        } else {
            try? session.updateApplicationContext(payload)
        }
        #endif
    }
    
    /// Requests the iPhone to send the library catalog to Apple Watch.
    public func requestLibraryCatalog() {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        let payload: [String: Any] = ["msgType": "requestCatalog"]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        #endif
    }
    
    // MARK: - Book Download Request (Watch -> Phone)
    
    /// Apple Watch requests the iPhone to transfer audio files for a specific book.
    public func requestBookDownload(bookID: UUID) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "msgType": "downloadRequest",
            "bookID": bookID.uuidString
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[WatchSyncManager] Failed to send download request: \(error.localizedDescription)")
            }
        }
        #endif
    }
    
    // MARK: - Playback State Synchronization
    
    /// Broadcasts the current playback position to the paired device.
    /// Uses real-time `sendMessage` if reachable; otherwise updates application context.
    public func syncPlaybackState(for item: LibraryItem) {
        let payload = PlaybackSyncPayload(
            bookID: item.id,
            position: item.currentPosition,
            isCompleted: item.isCompleted,
            lastUpdated: item.lastUpdated
        )
        sendSyncPayload(payload)
    }
    
    public func sendSyncPayload(_ payload: PlaybackSyncPayload) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let dict = payload.toDictionary()
        
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                print("[WatchSyncManager] Failed to send real-time sync message: \(error.localizedDescription)")
                try? session.updateApplicationContext(dict)
            }
        } else {
            try? session.updateApplicationContext(dict)
        }
        #endif
    }
    
    // MARK: - Conflict Resolution Engine
    
    /// Applies incoming sync updates to a `LibraryItem` using the invariant:
    /// "latest `lastUpdated` timestamp wins".
    ///
    /// Returns `true` if local item was updated, `false` if rejected as stale.
    @discardableResult
    public static func applySyncUpdate(
        payload: PlaybackSyncPayload,
        to item: LibraryItem
    ) -> Bool {
        guard payload.bookID == item.id else { return false }
        
        // Conflict resolution: latest timestamp wins
        if payload.lastUpdated > item.lastUpdated {
            item.currentPosition = payload.position
            item.isCompleted = payload.isCompleted
            item.lastUpdated = payload.lastUpdated
            return true
        }
        
        return false
    }
    
    // MARK: - Offline Audio File Sync (iOS -> watchOS)
    
    /// Queues all audio files of a single-file or multi-part audiobook for transfer to Apple Watch.
    public func transferBookToWatch(item: LibraryItem) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let tracks = item.playableTracks
        guard !tracks.isEmpty else { return }
        
        for (index, track) in tracks.enumerated() {
            guard let url = track.resolvedURL() else { continue }
            
            let metadata: [String: Any] = [
                "bookID": item.id.uuidString,
                "trackID": track.id.uuidString,
                "partIndex": index,
                "totalParts": tracks.count,
                "title": track.title,
                "totalDuration": track.totalDuration,
                "fileName": url.lastPathComponent
            ]
            
            let transfer = session.transferFile(url, metadata: metadata)
            let transferID = UUID().uuidString
            
            let status = WatchFileTransferStatus(
                id: transferID,
                bookID: item.id,
                partIndex: index,
                totalParts: tracks.count,
                title: track.title,
                fractionCompleted: transfer.progress.fractionCompleted,
                isTransferring: true
            )
            activeTransfers.append(status)
            
            // Observe progress updates
            let observation = transfer.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let idx = self.activeTransfers.firstIndex(where: { $0.id == transferID }) {
                        self.activeTransfers[idx].fractionCompleted = progress.fractionCompleted
                        if progress.fractionCompleted >= 1.0 {
                            self.activeTransfers[idx].isTransferring = false
                        }
                    }
                }
            }
            progressObservations.append(observation)
        }
        #endif
    }
    
    /// Check if a book currently has in-flight transfers.
    public func isTransferring(bookID: UUID) -> Bool {
        activeTransfers.contains(where: { $0.bookID == bookID && $0.isTransferring })
    }
    
    /// Overall transfer progress fraction for a book (0.0 ... 1.0).
    public func transferProgress(for bookID: UUID) -> Double {
        let matching = activeTransfers.filter { $0.bookID == bookID }
        guard !matching.isEmpty else { return 0.0 }
        let sum = matching.reduce(0.0) { $0 + $1.fractionCompleted }
        return sum / Double(matching.count)
    }
}

// MARK: - WCSessionDelegate

#if canImport(WatchConnectivity)
extension WatchSyncManager: WCSessionDelegate {
    
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }
    
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate session if user switches Apple Watch
        session.activate()
    }
    #endif
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }
    
    // MARK: - Receiving Messages
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingDictionary(message)
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncomingDictionary(applicationContext)
    }
    
    private nonisolated func handleIncomingDictionary(_ dict: [String: Any]) {
        let msgType = dict["msgType"] as? String
        
        // 1. Remote Command (Watch -> Phone)
        if msgType == "remoteCommand", let command = WatchRemoteCommand.from(dictionary: dict) {
            Task { @MainActor [weak self] in
                self?.onRemoteCommandReceived?(command)
            }
            return
        }
        
        // 2. Remote Playback State (Phone -> Watch)
        if msgType == "remotePlaybackState", let state = WatchRemotePlaybackState.from(dictionary: dict) {
            Task { @MainActor [weak self] in
                self?.remotePlaybackState = state
                self?.onRemotePlaybackStateReceived?(state)
            }
            return
        }
        
        // 3. Request Library Catalog (Watch -> Phone)
        if msgType == "requestCatalog" {
            Task { @MainActor [weak self] in
                self?.onLibraryCatalogRequested?()
            }
            return
        }
        
        // 4. Library Catalog Delivery (Phone -> Watch)
        if msgType == "libraryCatalog", let itemsRaw = dict["items"] as? [[String: Any]] {
            let summaries = itemsRaw.compactMap { WatchLibraryItemSummary.from(dictionary: $0) }
            Task { @MainActor [weak self] in
                self?.librarySummaries = summaries
                self?.onLibraryCatalogReceived?(summaries)
            }
            return
        }
        
        // 5. Download Request (Watch -> Phone)
        if msgType == "downloadRequest", let idStr = dict["bookID"] as? String, let uuid = UUID(uuidString: idStr) {
            Task { @MainActor [weak self] in
                self?.onDownloadRequestReceived?(uuid)
            }
            return
        }
        
        // 6. Playback Progress Sync
        if let payload = PlaybackSyncPayload.from(dictionary: dict) {
            Task { @MainActor [weak self] in
                self?.onPlaybackSyncReceived?(payload)
            }
            return
        }
    }
    
    // MARK: - Receiving Audio Files (iOS -> watchOS)
    
    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = ReceivedAudioMetadata(from: file.metadata ?? [:])
        let temporaryURL = file.fileURL
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Store inside Audiobooks/<bookID>/
        let bookFolder: URL
        if let bookID = metadata.bookID {
            bookFolder = documentsURL.appendingPathComponent("Audiobooks").appendingPathComponent(bookID.uuidString, isDirectory: true)
        } else {
            bookFolder = documentsURL.appendingPathComponent("Audiobooks").appendingPathComponent("Unknown", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: bookFolder, withIntermediateDirectories: true)
        
        let fileName = metadata.fileName ?? temporaryURL.lastPathComponent
        let destinationURL = bookFolder.appendingPathComponent(fileName)
        
        try? fileManager.removeItem(at: destinationURL)
        do {
            try fileManager.copyItem(at: temporaryURL, to: destinationURL)
            Task { @MainActor [weak self] in
                self?.onAudioFileReceived?(destinationURL, metadata)
            }
        } catch {
            print("[WatchSyncManager] Failed to persist received watch audio file: \(error.localizedDescription)")
        }
    }
}
#endif
