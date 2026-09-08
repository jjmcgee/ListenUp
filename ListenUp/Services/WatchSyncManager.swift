import Foundation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

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
            "bookID": bookID.uuidString,
            "position": position,
            "isCompleted": isCompleted,
            "lastUpdated": lastUpdated.timeIntervalSince1970
        ]
    }
    
    public static func from(dictionary: [String: Any]) -> PlaybackSyncPayload? {
        guard let idString = dictionary["bookID"] as? String,
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

/// Strongly-typed, sendable metadata delivered alongside transferred audio files.
public struct ReceivedAudioMetadata: Sendable {
    public let bookID: UUID?
    public let partIndex: Int?
    public let title: String?
    public let totalDuration: Double?
    
    public init(from dictionary: [String: Any]) {
        if let idStr = dictionary["bookID"] as? String {
            self.bookID = UUID(uuidString: idStr)
        } else {
            self.bookID = nil
        }
        self.partIndex = dictionary["partIndex"] as? Int
        self.title = dictionary["title"] as? String
        self.totalDuration = dictionary["totalDuration"] as? Double
    }
}

/// Information regarding an in-flight file transfer to watchOS.
public struct WatchFileTransferStatus: Identifiable, Sendable {
    public var id: String
    public var bookID: UUID
    public var partIndex: Int
    public var title: String
    public var fractionCompleted: Double
    public var isTransferring: Bool
}

/// Multi-device sync manager coordinating lightweight playback state and offline audio file transfers
/// via WatchConnectivity (`WCSession`).
///
/// Invariant: State conflict resolution follows "latest `lastUpdated` timestamp wins".
@Observable
@MainActor
public final class WatchSyncManager: NSObject {
    
    public static let shared = WatchSyncManager()
    
    /// Whether the paired device is currently reachable for real-time messaging.
    public private(set) var isReachable: Bool = false
    
    /// Tracks progress for active outgoing file transfers to Apple Watch.
    public private(set) var activeTransfers: [WatchFileTransferStatus] = []
    
    /// Callback triggered when an incoming progress update is received.
    public var onPlaybackSyncReceived: ((PlaybackSyncPayload) -> Void)?
    
    /// Callback triggered when an audio file has been delivered to this device.
    public var onAudioFileReceived: ((_ localURL: URL, _ metadata: ReceivedAudioMetadata) -> Void)?
    
    #if canImport(WatchConnectivity)
    private var session: WCSession?
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
                // Fallback to application context
                try? session.updateApplicationContext(dict)
            }
        } else {
            // Guaranteed delivery upon next wake
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
    
    /// Queues an audio file for transfer to Apple Watch with metadata.
    public func transferAudioFile(
        fileURL: URL,
        bookID: UUID,
        partIndex: Int,
        title: String,
        totalDuration: Double
    ) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        let metadata: [String: Any] = [
            "bookID": bookID.uuidString,
            "partIndex": partIndex,
            "title": title,
            "totalDuration": totalDuration
        ]
        
        let transfer = session.transferFile(fileURL, metadata: metadata)
        let transferID = UUID().uuidString
        
        let status = WatchFileTransferStatus(
            id: transferID,
            bookID: bookID,
            partIndex: partIndex,
            title: title,
            fractionCompleted: transfer.progress.fractionCompleted,
            isTransferring: true
        )
        activeTransfers.append(status)
        #endif
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
        guard let payload = PlaybackSyncPayload.from(dictionary: message) else { return }
        Task { @MainActor [weak self] in
            self?.onPlaybackSyncReceived?(payload)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let payload = PlaybackSyncPayload.from(dictionary: applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.onPlaybackSyncReceived?(payload)
        }
    }
    
    // MARK: - Receiving Audio Files
    
    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = ReceivedAudioMetadata(from: file.metadata ?? [:])
        let temporaryURL = file.fileURL
        
        // Copy file into sandbox Documents directory before system deletes temporary file
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let targetDirectory = documentsURL.appendingPathComponent("WatchSyncedAudio", isDirectory: true)
        try? fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        
        let destinationURL = targetDirectory.appendingPathComponent(temporaryURL.lastPathComponent)
        
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
