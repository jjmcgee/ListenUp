import Foundation
import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Sleep timer configuration presets.
public enum SleepTimerOption: Hashable, Sendable, Identifiable {
    case off
    case minutes(Int)
    case endOfChapter
    
    public var id: String {
        switch self {
        case .off: return "off"
        case .minutes(let mins): return "\(mins)m"
        case .endOfChapter: return "endOfChapter"
        }
    }
    
    public var title: String {
        switch self {
        case .off: return "Off"
        case .minutes(let mins): return "\(mins) minutes"
        case .endOfChapter: return "End of Chapter"
        }
    }
    
    public var durationInSeconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .minutes(let mins): return TimeInterval(mins * 60)
        case .endOfChapter: return nil
        }
    }
}

/// Robust, Swift 6 compliant audio playback engine for ListenUp.
///
/// Key Architectural Features:
/// - Continuous virtual timeline across multi-part audiobooks using `AVQueuePlayer`.
/// - Automatic track chaining without physical file concatenation.
/// - System-level integration with `AVAudioSession`, `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter`.
/// - Audio interruption, route change handling, and customizable sleep timers.
/// - Strictly bound to `@MainActor`.
@Observable
@MainActor
public final class AudioPlayerManager {
    
    // MARK: - Observable Playback State
    
    /// The parent item currently loaded (either a single file or a multi-part book).
    public private(set) var currentItem: LibraryItem?
    
    /// The active physical track being played inside the queue.
    public private(set) var currentTrack: LibraryItem?
    
    /// Zero-based index of the currently playing track in the multi-part sequence.
    public private(set) var currentTrackIndex: Int = 0
    
    /// Indicates whether the audio engine is actively producing sound.
    public private(set) var isPlaying: Bool = false
    
    /// Virtual continuous playback timeline position in seconds.
    public private(set) var currentTime: Double = 0.0
    
    /// Total virtual continuous duration in seconds across all segments.
    public private(set) var totalDuration: Double = 0.0
    
    /// Active playback speed multiplier.
    public var playbackRate: Float = 1.0 {
        didSet {
            applyPlaybackRate()
        }
    }
    
    /// True while the user is actively dragging the scrubber slider.
    public private(set) var isScrubbing: Bool = false
    
    /// Active sleep timer setting.
    public private(set) var activeSleepTimerOption: SleepTimerOption = .off
    
    /// Countdown seconds remaining on the active sleep timer.
    public private(set) var sleepTimerRemaining: TimeInterval? = nil
    
    /// Closure invoked whenever progress updates should be persisted to SwiftData.
    public var onPositionUpdated: ((_ item: LibraryItem, _ position: Double) -> Void)?
    
    // MARK: - Internal Audio Engine Properties
    
    private var queuePlayer: AVQueuePlayer?
    private var timeObserverToken: Any?
    private var itemDidPlayToEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var lastPersistedPosition: Double = 0.0
    private var sleepTimerTask: Task<Void, Never>?
    private var isConfiguringQueue: Bool = false
    
    // MARK: - Initialization & Lifecycle
    
    public init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
    }
    
    /// Releases audio resources, observers, and active timers.
    public func teardown() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        teardownPlayer()
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    
    // MARK: - Audio Session Configuration
    
    private func setupAudioSession() {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("[AudioPlayerManager] Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func setupNotifications() {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
        
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
        #endif
    }
    
    // MARK: - Playback Control API
    
    /// Loads an item (singleFile or multiPart) and initiates playback at its last saved position.
    public func play(item: LibraryItem) {
        if currentItem?.id == item.id && queuePlayer != nil {
            resume()
            return
        }
        
        loadItem(item, startAtPosition: item.currentPosition)
        resume()
    }
    
    /// Toggles between play and pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    /// Resumes playback.
    public func resume() {
        guard let player = queuePlayer else { return }
        
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        
        player.play()
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    /// Pauses playback and persists the current position.
    public func pause() {
        queuePlayer?.pause()
        isPlaying = false
        persistCurrentPosition()
        updateNowPlayingInfo()
    }
    
    /// Stops playback, clears the loaded item and player queue, and resets now playing info.
    public func stop() {
        pause()
        teardownPlayer()
        currentItem = nil
        currentTrack = nil
        currentTrackIndex = 0
        currentTime = 0.0
        totalDuration = 0.0
        updateNowPlayingInfo()
    }
    
    /// Skips forward by a given number of seconds (default 30s).
    public func skipForward(by seconds: Double = 30.0) {
        seek(to: currentTime + seconds)
    }
    
    /// Skips backward by a given number of seconds (default 15s).
    public func skipBackward(by seconds: Double = 15.0) {
        seek(to: currentTime - seconds)
    }
    
    /// Seeks to a specific timestamp on the virtual continuous timeline.
    public func seek(to targetVirtualTime: Double) {
        guard let item = currentItem else { return }
        let clampedTime = min(max(targetVirtualTime, 0.0), totalDuration)
        
        currentTime = clampedTime
        
        guard let (segment, localOffset) = item.segment(at: clampedTime) else {
            return
        }
        
        if segment.trackIndex == currentTrackIndex, let currentItem = queuePlayer?.currentItem {
            // Target is within the currently loaded physical track
            let targetCMTime = CMTime(seconds: localOffset, preferredTimescale: 1000)
            currentItem.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateNowPlayingInfo()
                    self?.persistCurrentPosition()
                }
            }
        } else {
            // Target spans into a different track segment: rebuild the remaining queue from this segment
            rebuildQueue(fromTrackIndex: segment.trackIndex, initialOffset: localOffset)
        }
    }
    
    /// Begins an interactive scrub operation from the UI.
    public func startScrubbing() {
        isScrubbing = true
    }
    
    /// Updates virtual time preview while the user drags the scrubber.
    public func scrubUpdate(to virtualTime: Double) {
        currentTime = min(max(virtualTime, 0.0), totalDuration)
    }
    
    /// Completes the scrubbing gesture, seeking to the final virtual timestamp.
    public func endScrubbing(to virtualTime: Double) {
        isScrubbing = false
        seek(to: virtualTime)
    }
    
    /// Adjusts playback rate multiplier.
    public func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }
    
    private func applyPlaybackRate() {
        if isPlaying {
            queuePlayer?.rate = playbackRate
        }
        updateNowPlayingInfo()
    }
    
    // MARK: - Queue & Virtual Timeline Engine
    
    private func loadItem(_ item: LibraryItem, startAtPosition: Double) {
        currentItem = item
        totalDuration = item.totalDuration
        
        let initialVirtualTime = min(max(startAtPosition, 0.0), totalDuration)
        currentTime = initialVirtualTime
        
        let targetSegment = item.segment(at: initialVirtualTime)
        let startIndex = targetSegment?.segment.trackIndex ?? 0
        let startOffset = targetSegment?.localOffset ?? 0.0
        
        rebuildQueue(fromTrackIndex: startIndex, initialOffset: startOffset)
    }
    
    private func rebuildQueue(fromTrackIndex startIndex: Int, initialOffset: Double) {
        isConfiguringQueue = true
        defer { isConfiguringQueue = false }
        
        guard let item = currentItem else { return }
        let tracks = item.playableTracks
        guard startIndex >= 0 && startIndex < tracks.count else { return }
        
        currentTrackIndex = startIndex
        currentTrack = tracks[startIndex]
        
        // Teardown existing queue player and observers
        teardownPlayer()
        
        // Build AVPlayerItems for startIndex and subsequent segments
        var playerItems: [AVPlayerItem] = []
        for index in startIndex..<tracks.count {
            let track = tracks[index]
            guard let url = track.resolvedURL() else { continue }
            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            playerItems.append(playerItem)
        }
        
        guard let firstItem = playerItems.first else { return }
        
        let player = AVQueuePlayer(items: playerItems)
        player.actionAtItemEnd = .advance
        
        if initialOffset > 0 {
            let cmOffset = CMTime(seconds: initialOffset, preferredTimescale: 1000)
            firstItem.seek(to: cmOffset, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
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
    
    private func setupTimeObserver(for player: AVQueuePlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePeriodicTimeUpdate()
            }
        }
    }
    
    private func handlePeriodicTimeUpdate() {
        guard !isScrubbing, !isConfiguringQueue, let item = currentItem, let player = queuePlayer else { return }
        
        let localSeconds = player.currentTime().seconds
        guard !localSeconds.isNaN && !localSeconds.isInfinite else { return }
        
        let virtualT = item.virtualPosition(trackIndex: currentTrackIndex, localOffset: localSeconds)
        currentTime = virtualT
        
        // Debounce SwiftData persistence to once every 5 seconds or significant scrub
        if abs(virtualT - lastPersistedPosition) >= 5.0 {
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
                self?.handleTrackDidPlayToEnd()
            }
        }
    }
    
    private func handleTrackDidPlayToEnd() {
        guard let item = currentItem else { return }
        
        if activeSleepTimerOption == .endOfChapter {
            pause()
            setSleepTimer(.off)
            return
        }
        
        let tracks = item.playableTracks
        let nextIndex = currentTrackIndex + 1
        
        if nextIndex < tracks.count {
            currentTrackIndex = nextIndex
            currentTrack = tracks[nextIndex]
            updateNowPlayingInfo()
            persistCurrentPosition()
        } else {
            // All segments completed
            currentTime = totalDuration
            item.isCompleted = true
            persistCurrentPosition()
            pause()
        }
    }
    
    private func persistCurrentPosition() {
        guard let item = currentItem else { return }
        item.currentPosition = currentTime
        item.lastUpdated = Date()
        lastPersistedPosition = currentTime
        onPositionUpdated?(item, currentTime)
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
    
    // MARK: - Sleep Timer Engine
    
    public func setSleepTimer(_ option: SleepTimerOption) {
        activeSleepTimerOption = option
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        
        guard let seconds = option.durationInSeconds else {
            sleepTimerRemaining = nil
            return
        }
        
        sleepTimerRemaining = seconds
        
        sleepTimerTask = Task { @MainActor [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                self?.sleepTimerRemaining = remaining
            }
            
            // Time expired: smooth fadeout and pause
            self?.pause()
            self?.activeSleepTimerOption = .off
            self?.sleepTimerRemaining = nil
        }
    }
    
    // MARK: - System Remote Command Center Integration
    
    private func setupRemoteCommandCenter() {
        #if os(iOS)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
        
        #if canImport(MediaPlayer)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resume()
            }
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }
        
        // Toggle Play/Pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }
        
        // Skip Forward (+30s)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.skipForward(by: skipEvent.interval)
            }
            return .success
        }
        
        // Skip Backward (-15s)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.skipBackward(by: skipEvent.interval)
            }
            return .success
        }
        
        // Change Playback Position (Lock Screen Scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(to: posEvent.positionTime)
            }
            return .success
        }
        #endif
    }
    
    // MARK: - System Now Playing Info Center
    
    private func updateNowPlayingInfo() {
        #if canImport(MediaPlayer)
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [:]
        
        // Title: If multi-part, show Book Title with Track/Part Subtitle if available
        if item.kind == .multiPart, let track = currentTrack {
            info[MPMediaItemPropertyTitle] = "\(item.title) — \(track.title)"
        } else {
            info[MPMediaItemPropertyTitle] = item.title
        }
        
        if let author = item.author {
            info[MPMediaItemPropertyArtist] = author
        }
        
        if totalDuration > 0 && !totalDuration.isNaN && !totalDuration.isInfinite {
            info[MPMediaItemPropertyPlaybackDuration] = totalDuration
        }
        if !currentTime.isNaN && !currentTime.isInfinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        
        // Embedded artwork
        if let data = item.artworkData,
           let image = PlatformImage(data: data),
           image.size.width > 0,
           image.size.height > 0 {
            #if os(iOS) || os(tvOS) || os(visionOS)
            let size = image.size
            let artwork = MPMediaItemArtwork(boundsSize: size) { @Sendable _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
            #endif
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }
    
    // MARK: - System Notifications
    
    #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
    private func handleAudioInterruption(typeValue: UInt, optionsValue: UInt?) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Automatically pause when headphones are unplugged or Bluetooth disconnects
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    #endif
}

// MARK: - Cross-Platform Image Typealias

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif
