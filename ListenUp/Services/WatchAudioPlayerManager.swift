import Foundation
import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Standalone audio player engine for Apple Watch.
/// Manages offline playback of downloaded audiobooks via `AVQueuePlayer` / `AVPlayer`
/// and integrates with watchOS `AVAudioSession` and `MPNowPlayingInfoCenter`.
@Observable
@MainActor
public final class WatchAudioPlayerManager {
    
    public static let shared = WatchAudioPlayerManager()
    
    // MARK: - Observable State
    
    public private(set) var currentBookID: UUID?
    public private(set) var currentBookTitle: String = ""
    public private(set) var currentBookAuthor: String?
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: Double = 0.0
    public private(set) var totalDuration: Double = 0.0
    public var playbackRate: Float = 1.0 {
        didSet {
            applyPlaybackRate()
        }
    }
    
    public private(set) var chapters: [ChapterInfo] = []
    public private(set) var currentTrackIndex: Int = 0
    
    // Track durations for multi-part continuous virtual timeline
    private var trackDurations: [Double] = []
    private var trackURLs: [URL] = []
    
    // MARK: - Internal Player
    
    private var queuePlayer: AVQueuePlayer?
    private var timeObserverToken: Any?
    private var itemDidPlayToEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var lastPersistedPosition: Double = 0.0
    
    public var onPositionUpdated: ((_ bookID: UUID, _ position: Double, _ isCompleted: Bool) -> Void)?
    
    public init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        #if os(watchOS) || os(iOS)
        Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
            } catch {
                print("[WatchAudioPlayerManager] AVAudioSession config failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
    
    private func setupNotifications() {
        #if os(watchOS) || os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeVal = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            let optionsVal = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            
            Task { @MainActor [weak self] in
                if type == .began {
                    self?.pause()
                } else if type == .ended {
                    if let optVal = optionsVal,
                       AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) {
                        self?.resume()
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - Playback Control API
    
    /// Starts playback of a downloaded book on Apple Watch.
    public func play(
        bookID: UUID,
        title: String,
        author: String?,
        urls: [URL],
        startPosition: Double = 0.0
    ) {
        if currentBookID == bookID && queuePlayer != nil {
            resume()
            return
        }
        
        self.currentBookID = bookID
        self.currentBookTitle = title
        self.currentBookAuthor = author
        self.trackURLs = urls
        
        // Calculate durations of each track
        calculateTrackDurationsAndLoad(startPosition: startPosition)
    }
    
    private func calculateTrackDurationsAndLoad(startPosition: Double) {
        let urls = self.trackURLs
        
        Task.detached(priority: .userInitiated) {
            var durations: [Double] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                if let duration = try? await asset.load(.duration) {
                    durations.append(max(0.0, duration.seconds))
                } else {
                    durations.append(0.0)
                }
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.trackDurations = durations
                self.totalDuration = durations.reduce(0.0, +)
                self.loadQueue(startAtPosition: startPosition)
                self.resume()
            }
        }
    }
    
    private func loadQueue(startAtPosition: Double) {
        let clampedTime = min(max(startAtPosition, 0.0), totalDuration)
        self.currentTime = clampedTime
        
        // Locate starting track index and offset
        var cumulative: Double = 0.0
        var targetIndex = 0
        var targetOffset: Double = 0.0
        
        for (idx, dur) in trackDurations.enumerated() {
            if clampedTime >= cumulative && clampedTime < cumulative + dur {
                targetIndex = idx
                targetOffset = clampedTime - cumulative
                break
            }
            cumulative += dur
        }
        
        rebuildQueue(fromIndex: targetIndex, offset: targetOffset)
    }
    
    private func rebuildQueue(fromIndex startIndex: Int, offset: Double) {
        teardownPlayer()
        
        guard startIndex >= 0 && startIndex < trackURLs.count else { return }
        self.currentTrackIndex = startIndex
        
        var playerItems: [AVPlayerItem] = []
        for idx in startIndex..<trackURLs.count {
            let item = AVPlayerItem(url: trackURLs[idx])
            playerItems.append(item)
        }
        
        guard let first = playerItems.first else { return }
        
        let player = AVQueuePlayer(items: playerItems)
        player.actionAtItemEnd = .advance
        
        if offset > 0 {
            let cmTime = CMTime(seconds: offset, preferredTimescale: 1000)
            first.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        }
        
        self.queuePlayer = player
        setupTimeObserver(for: player)
        setupItemEndObserver()
        
        if isPlaying {
            player.play()
            player.rate = playbackRate
        }
        
        updateNowPlayingInfo()
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    public func resume() {
        guard let player = queuePlayer else { return }
        
        #if os(watchOS) || os(iOS)
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        #endif
        
        player.play()
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    public func pause() {
        queuePlayer?.pause()
        isPlaying = false
        persistCurrentPosition()
        updateNowPlayingInfo()
    }
    
    public func stop() {
        pause()
        teardownPlayer()
        currentBookID = nil
        currentBookTitle = ""
        currentBookAuthor = nil
        currentTime = 0.0
        totalDuration = 0.0
        updateNowPlayingInfo()
    }
    
    public func skipForward(by seconds: Double = 30.0) {
        seek(to: currentTime + seconds)
    }
    
    public func skipBackward(by seconds: Double = 15.0) {
        seek(to: currentTime - seconds)
    }
    
    public func seek(to targetTime: Double) {
        let clamped = min(max(targetTime, 0.0), totalDuration)
        self.currentTime = clamped
        
        var cumulative: Double = 0.0
        var targetIndex = 0
        var targetOffset: Double = 0.0
        
        for (idx, dur) in trackDurations.enumerated() {
            if clamped >= cumulative && clamped < cumulative + dur {
                targetIndex = idx
                targetOffset = clamped - cumulative
                break
            }
            cumulative += dur
        }
        
        if targetIndex == currentTrackIndex, let currentItem = queuePlayer?.currentItem {
            let cmTime = CMTime(seconds: targetOffset, preferredTimescale: 1000)
            currentItem.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateNowPlayingInfo()
                    self?.persistCurrentPosition()
                }
            }
        } else {
            rebuildQueue(fromIndex: targetIndex, offset: targetOffset)
        }
    }
    
    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
    }
    
    private func applyPlaybackRate() {
        if isPlaying {
            queuePlayer?.rate = playbackRate
        }
        updateNowPlayingInfo()
    }
    
    // MARK: - Observers
    
    private func setupTimeObserver(for player: AVQueuePlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePeriodicTime()
            }
        }
    }
    
    private func handlePeriodicTime() {
        guard let player = queuePlayer else { return }
        let localSeconds = player.currentTime().seconds
        guard !localSeconds.isNaN && !localSeconds.isInfinite else { return }
        
        var cumulative: Double = 0.0
        for i in 0..<currentTrackIndex {
            if i < trackDurations.count {
                cumulative += trackDurations[i]
            }
        }
        
        currentTime = min(cumulative + localSeconds, totalDuration)
        
        if abs(currentTime - lastPersistedPosition) >= 5.0 {
            persistCurrentPosition()
        }
    }
    
    private func setupItemEndObserver() {
        itemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnded()
            }
        }
    }
    
    private func handleTrackEnded() {
        let nextIndex = currentTrackIndex + 1
        if nextIndex < trackURLs.count {
            currentTrackIndex = nextIndex
            updateNowPlayingInfo()
            persistCurrentPosition()
        } else {
            currentTime = totalDuration
            persistCurrentPosition(isCompleted: true)
            pause()
        }
    }
    
    private func persistCurrentPosition(isCompleted: Bool = false) {
        guard let bookID = currentBookID else { return }
        lastPersistedPosition = currentTime
        onPositionUpdated?(bookID, currentTime, isCompleted)
    }
    
    private func teardownPlayer() {
        if let token = timeObserverToken {
            queuePlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = itemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            itemDidPlayToEndObserver = nil
        }
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
    }
    
    // MARK: - Now Playing & Remote Command Center
    
    private func setupRemoteCommandCenter() {
        #if canImport(MediaPlayer)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.skipForward(by: skipEvent.interval) }
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.skipBackward(by: skipEvent.interval) }
            return .success
        }
        #endif
    }
    
    private func updateNowPlayingInfo() {
        #if canImport(MediaPlayer)
        guard currentBookID != nil else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentBookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        
        if let author = currentBookAuthor {
            info[MPMediaItemPropertyArtist] = author
        }
        if totalDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = totalDuration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }
}
