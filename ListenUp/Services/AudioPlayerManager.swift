import Foundation
import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if canImport(CoreMotion)
import CoreMotion
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

extension Notification.Name {
    public static let deviceDidShake = Notification.Name("ListenUpDeviceDidShake")
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
    
    /// Shared singleton instance for unified access across iOS UI, CarPlay, and system events.
    public static let shared = AudioPlayerManager()
    
    /// Broadcast whenever audio state, now playing info, or active track/chapter changes.
    public static let playbackStateDidChangeNotification = Notification.Name("AudioPlayerManager.playbackStateDidChangeNotification")
    
    // MARK: - Observable Playback State
    
    /// The parent item currently loaded (either a single file or a multi-part book).
    public private(set) var currentItem: LibraryItem?
    
    /// Holds a book that just completed playback and is awaiting user decision on whether to delete audio files to save storage.
    public var bookPendingDeletionPrompt: LibraryItem? = nil
    
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
    
    /// Extracted chapter marks for the currently loaded audiobook.
    public private(set) var chapters: [ChapterInfo] = []
    
    /// Indicates whether chapter extraction is actively in progress.
    public private(set) var isLoadingChapters: Bool = false
    
    /// The currently active chapter based on continuous virtual playback time.
    public var currentChapter: ChapterInfo? {
        guard !chapters.isEmpty else { return nil }
        
        for chapter in chapters {
            if currentTime >= chapter.startTime && currentTime < chapter.endTime {
                return chapter
            }
        }
        
        if let last = chapters.last, currentTime >= last.startTime {
            return last
        }
        
        return chapters.first
    }
    
    /// Zero-based index of the currently active chapter.
    public var currentChapterIndex: Int? {
        currentChapter?.index
    }
    
    /// Elapsed time in seconds inside the currently active chapter.
    public var currentChapterElapsed: Double {
        guard let chapter = currentChapter else { return currentTime }
        return min(max(0.0, currentTime - chapter.startTime), chapter.duration)
    }
    
    /// Remaining time in seconds inside the currently active chapter.
    public var currentChapterRemaining: Double {
        guard let chapter = currentChapter else { return max(0.0, totalDuration - currentTime) }
        return min(max(0.0, chapter.endTime - currentTime), chapter.duration)
    }
    
    /// Playback completion fraction within the active chapter (`0.0 ... 1.0`).
    public var currentChapterProgress: Double {
        guard let chapter = currentChapter, chapter.duration > 0 else {
            return totalDuration > 0 ? min(max(currentTime / totalDuration, 0.0), 1.0) : 0.0
        }
        return min(max(currentChapterElapsed / chapter.duration, 0.0), 1.0)
    }
    
    /// Closure invoked whenever progress updates should be persisted to SwiftData.
    public var onPositionUpdated: ((_ item: LibraryItem, _ position: Double) -> Void)?
    
    // MARK: - Internal Audio Engine Properties
    
    private var queuePlayer: AVQueuePlayer?
    private var timeObserverToken: Any?
    private var itemDidPlayToEndObserver: NSObjectProtocol?
    private var didBecomeInactiveObserver: NSObjectProtocol?
    private var resumptionRecommendationObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption: Bool = false
    private var lastPausedTimestamp: Date?
    private var didPauseAtBoundary: Bool = false
    private var lastPersistedPosition: Double = 0.0
    private var lastListeningRecordedPosition: Double?
    private var sleepTimerTask: Task<Void, Never>?
    private var isConfiguringQueue: Bool = false
    
    // MARK: - User Settings Preferences
    
    /// Interval in seconds for skipping forward. Defaults to 30s.
    public var skipForwardInterval: Double {
        let val = UserDefaults.standard.double(forKey: "skipForwardInterval")
        return val > 0 ? val : 30.0
    }
    
    /// Interval in seconds for skipping backward. Defaults to 15s.
    public var skipBackwardInterval: Double {
        let val = UserDefaults.standard.double(forKey: "skipBackwardInterval")
        return val > 0 ? val : 15.0
    }
    
    /// Indicates whether smart rewind (2 seconds upon resume) is enabled. Defaults to true.
    public var isSmartRewindEnabled: Bool {
        if UserDefaults.standard.object(forKey: "smartRewindEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "smartRewindEnabled")
    }
    
    /// Indicates whether playback auto-advances to the next chapter or track. Defaults to true.
    public var isContinuousPlaybackEnabled: Bool {
        if UserDefaults.standard.object(forKey: "continuousPlayback") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "continuousPlayback")
    }
    
    /// Indicates whether shake-to-extend sleep timer is enabled. Defaults to false.
    public var isShakeToExtendSleepTimerEnabled: Bool {
        UserDefaults.standard.bool(forKey: "shakeToExtendSleepTimer")
    }
    
    /// Indicates whether the player is currently in the grace period waiting for a shake to extend.
    public private(set) var isWaitingForShakeToExtend: Bool = false
    
    #if (os(iOS) || os(watchOS)) && canImport(CoreMotion)
    @ObservationIgnored private var motionManager: CMMotionManager?
    #endif
    private var shakeDetectionTask: Task<Void, Never>?
    private var shakeNotificationObserver: NSObjectProtocol?
    
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
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        if let observer = didBecomeInactiveObserver {
            NotificationCenter.default.removeObserver(observer)
            didBecomeInactiveObserver = nil
        }
        if let observer = resumptionRecommendationObserver {
            NotificationCenter.default.removeObserver(observer)
            resumptionRecommendationObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = shakeNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            shakeNotificationObserver = nil
        }
        stopShakeToExtendDetection()
    }

    
    // MARK: - Audio Session Configuration
    
    private func setupAudioSession() {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
            } catch {
                print("[AudioPlayerManager] Failed to configure AVAudioSession: \(error.localizedDescription)")
            }
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
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
        
        didBecomeInactiveObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
        }
        
        resumptionRecommendationObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            let shouldResume = context?.recommendation == .shouldResume
            Task { @MainActor [weak self] in
                if shouldResume {
                    self?.resume()
                }
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
        
        shakeNotificationObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidShake,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isShakeToExtendSleepTimerEnabled else { return }
                if self.isWaitingForShakeToExtend || self.sleepTimerRemaining != nil {
                    self.extendSleepTimer(by: 300.0)
                }
            }
        }
    }
    
    // MARK: - Playback Control API
    
    /// Loads an item (singleFile or multiPart) and initiates playback at its last saved position.
    public func play(item: LibraryItem) {
        guard !item.isFileOffloaded else { return }
        
        if currentItem?.id == item.id && queuePlayer != nil {
            resume()
            return
        }
        
        loadItem(item, startAtPosition: item.currentPosition)
        resume()
    }
    
    /// Prepares an item for playback at its saved position without starting playback.
    public func prepare(item: LibraryItem) {
        guard !item.isFileOffloaded else { return }
        if currentItem?.id == item.id && queuePlayer != nil {
            return
        }
        loadItem(item, startAtPosition: item.currentPosition)
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    /// Toggles between play and pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            if queuePlayer == nil, let item = currentItem {
                loadItem(item, startAtPosition: item.currentPosition)
            }
            resume()
        }
    }
    
    /// Resumes playback.
    public func resume() {
        guard let player = queuePlayer else { return }
        
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlayerManager] Failed to activate AVAudioSession: \(error.localizedDescription)")
        }
        #endif
        
        // Smart Rewind: rewind 2s when resuming after being paused for more than 3 seconds
        if isSmartRewindEnabled && !didPauseAtBoundary,
           let pausedAt = lastPausedTimestamp,
           Date().timeIntervalSince(pausedAt) >= 3.0,
           currentTime > 0 {
            let rewindTime = max(0.0, currentTime - 2.0)
            seek(to: rewindTime)
        }
        lastPausedTimestamp = nil
        didPauseAtBoundary = false
        
        player.play()
        player.rate = playbackRate
        isPlaying = true
        lastListeningRecordedPosition = currentTime
        updateNowPlayingInfo()
    }
    
    /// Pauses playback and persists the current position.
    public func pause() {
        queuePlayer?.pause()
        isPlaying = false
        lastPausedTimestamp = Date()
        if let lastRecorded = lastListeningRecordedPosition {
            let delta = currentTime - lastRecorded
            if delta > 0 && delta <= 30.0 {
                ListeningStatsStore.shared.recordListening(seconds: delta)
            }
        }
        lastListeningRecordedPosition = currentTime
        persistCurrentPosition()
        updateNowPlayingInfo()
    }
    
    /// Stops playback, clears the loaded item and player queue, and resets now playing info.
    public func stop() {
        pause()
        teardownPlayer()
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        lastPausedTimestamp = nil
        didPauseAtBoundary = false
        currentItem = nil
        currentTrack = nil
        currentTrackIndex = 0
        currentTime = 0.0
        totalDuration = 0.0
        chapters = []
        isLoadingChapters = false
        updateNowPlayingInfo()
    }
    
    /// Skips forward by a given number of seconds (defaults to skipForwardInterval preference).
    public func skipForward(by seconds: Double? = nil) {
        let interval = seconds ?? skipForwardInterval
        seek(to: currentTime + interval)
    }
    
    /// Skips backward by a given number of seconds (defaults to skipBackwardInterval preference).
    public func skipBackward(by seconds: Double? = nil) {
        let interval = seconds ?? skipBackwardInterval
        seek(to: currentTime - interval)
    }
    
    /// Seeks to a specific timestamp on the virtual continuous timeline.
    public func seek(to targetVirtualTime: Double) {
        lastPausedTimestamp = nil
        didPauseAtBoundary = false
        guard let item = currentItem else { return }
        let clampedTime = min(max(targetVirtualTime, 0.0), totalDuration)
        
        currentTime = clampedTime
        lastListeningRecordedPosition = clampedTime
        
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
    
    /// Cycles through standard audiobook playback speeds (1.0x -> 1.25x -> 1.5x -> 1.75x -> 2.0x -> 0.75x -> 1.0x).
    public func cyclePlaybackRate() {
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        if let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.01 }) {
            let nextIndex = (currentIndex + 1) % rates.count
            setPlaybackRate(rates[nextIndex])
        } else {
            setPlaybackRate(1.0)
        }
    }
    
    private func applyPlaybackRate() {
        if isPlaying {
            queuePlayer?.rate = playbackRate
        }
        updateNowPlayingInfo()
    }
    
    // MARK: - Chapter Navigation & Management
    
    /// Forces re-extraction of chapter marks for the currently loaded audiobook.
    public func reloadChapters() {
        guard let item = currentItem else { return }
        loadChapters(for: item)
    }
    
    /// Seeks playback to the start of a specified chapter.
    public func skipToChapter(_ chapter: ChapterInfo) {
        seek(to: chapter.startTime)
    }
    
    /// Skips to the next chapter if one exists.
    public func skipToNextChapter() {
        guard !chapters.isEmpty,
              let current = currentChapter,
              let arrayIndex = chapters.firstIndex(where: { $0.id == current.id }),
              arrayIndex + 1 < chapters.count else { return }
        seek(to: chapters[arrayIndex + 1].startTime)
    }
    
    /// Skips to the previous chapter, or rewinds to start of current chapter if played > 3s.
    public func skipToPreviousChapter() {
        guard !chapters.isEmpty, let current = currentChapter else { return }
        
        if currentTime - current.startTime > 3.0 {
            seek(to: current.startTime)
        } else if let arrayIndex = chapters.firstIndex(where: { $0.id == current.id }), arrayIndex > 0 {
            seek(to: chapters[arrayIndex - 1].startTime)
        } else {
            seek(to: 0.0)
        }
    }
    
    private func loadChapters(for item: LibraryItem) {
        isLoadingChapters = true
        let itemId = item.id
        let isSingle = item.kind == .singleFile
        
        // Convert SwiftData model to Sendable descriptors on MainActor before crossing into Task
        let trackDescriptors: [TrackDescriptor]
        if isSingle {
            trackDescriptors = [
                TrackDescriptor(
                    url: item.resolvedURL(),
                    title: item.title,
                    duration: item.totalDuration,
                    startVirtualTime: 0.0
                )
            ]
        } else {
            trackDescriptors = item.segments.map { segment in
                TrackDescriptor(
                    url: segment.track.resolvedURL(),
                    title: segment.track.title,
                    duration: segment.duration,
                    startVirtualTime: segment.startVirtualTime
                )
            }
        }
        
        Task { [weak self] in
            let extracted = await ChapterExtractor.extractChapters(for: trackDescriptors, isSingleFile: isSingle)
            await MainActor.run { [weak self] in
                guard let self = self, self.currentItem?.id == itemId else { return }
                self.chapters = extracted
                self.isLoadingChapters = false
                self.updateNowPlayingInfo()
            }
        }
    }
    
    // MARK: - Queue & Virtual Timeline Engine
    
    private func loadItem(_ item: LibraryItem, startAtPosition: Double) {
        currentItem = item
        totalDuration = item.totalDuration
        lastPausedTimestamp = startAtPosition > 0 ? Date.distantPast : nil
        didPauseAtBoundary = false
        
        let initialVirtualTime = min(max(startAtPosition, 0.0), totalDuration)
        currentTime = initialVirtualTime
        
        let targetSegment = item.segment(at: initialVirtualTime)
        let startIndex = targetSegment?.segment.trackIndex ?? 0
        let startOffset = targetSegment?.localOffset ?? 0.0
        
        loadChapters(for: item)
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
        
        // Handle end-of-chapter sleep timer for embedded chapters
        if activeSleepTimerOption == .endOfChapter, let chapter = currentChapter {
            if currentTime >= chapter.endTime - 0.5 {
                pause()
                setSleepTimer(.off)
                if isShakeToExtendSleepTimerEnabled {
                    startShakeToExtendDetection(duration: 60.0)
                }
                return
            }
        }
        
        // Handle continuous playback toggle for embedded chapters
        if !isContinuousPlaybackEnabled, let chapter = currentChapter, chapter.index < (chapters.last?.index ?? 0) {
            if currentTime >= chapter.endTime - 0.3 {
                if let nextChapter = chapters.first(where: { $0.index == chapter.index + 1 }) {
                    seek(to: nextChapter.startTime)
                }
                didPauseAtBoundary = true
                pause()
                return
            }
        }
        
        // Debounce SwiftData persistence to once every 5 seconds or significant scrub
        if abs(virtualT - lastPersistedPosition) >= 5.0 {
            if let lastRecorded = lastListeningRecordedPosition, isPlaying {
                let delta = virtualT - lastRecorded
                if delta > 0 && delta <= 30.0 {
                    ListeningStatsStore.shared.recordListening(seconds: delta)
                }
            }
            lastListeningRecordedPosition = virtualT
            persistCurrentPosition()
        }
    }
    
    private func setupItemEndObserver() {
        itemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
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
            if !isContinuousPlaybackEnabled {
                currentTrackIndex = nextIndex
                currentTrack = tracks[nextIndex]
                currentTime = item.virtualPosition(trackIndex: nextIndex, localOffset: 0.0)
                updateNowPlayingInfo()
                persistCurrentPosition()
                didPauseAtBoundary = true
                pause()
                return
            }
            
            currentTrackIndex = nextIndex
            currentTrack = tracks[nextIndex]
            updateNowPlayingInfo()
            persistCurrentPosition()
        } else {
            // All segments completed
            currentTime = totalDuration
            item.isCompleted = true
            item.completedDate = item.completedDate ?? Date()
            persistCurrentPosition()
            pause()
            
            if !item.isFileOffloaded {
                bookPendingDeletionPrompt = item
            }
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
            
            // If shake to extend is enabled, start listening for shake gestures
            if self?.isShakeToExtendSleepTimerEnabled == true {
                self?.startShakeToExtendDetection(duration: 60.0)
            }
        }
    }
    
    // MARK: - Shake to Extend Sleep Timer
    
    /// Starts monitoring accelerometer and device motion for shake gestures to extend sleep timer.
    public func startShakeToExtendDetection(duration: TimeInterval = 60.0) {
        guard isShakeToExtendSleepTimerEnabled else { return }
        isWaitingForShakeToExtend = true
        shakeDetectionTask?.cancel()
        
        #if (os(iOS) || os(watchOS)) && canImport(CoreMotion)
        let manager = motionManager ?? CMMotionManager()
        motionManager = manager
        
        if manager.isAccelerometerAvailable {
            manager.accelerometerUpdateInterval = 0.1
            manager.startAccelerometerUpdates()
        }
        #endif
        
        shakeDetectionTask = Task { @MainActor [weak self] in
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < duration {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                #if (os(iOS) || os(watchOS)) && canImport(CoreMotion)
                if let data = self?.motionManager?.accelerometerData {
                    let acc = data.acceleration
                    let magnitude = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                    if magnitude > 2.0 {
                        self?.extendSleepTimer(by: 300.0)
                        return
                    }
                }
                #endif
            }
            self?.stopShakeToExtendDetection()
        }
    }
    
    /// Stops accelerometer monitoring for shake events.
    public func stopShakeToExtendDetection() {
        isWaitingForShakeToExtend = false
        shakeDetectionTask?.cancel()
        shakeDetectionTask = nil
        #if (os(iOS) || os(watchOS)) && canImport(CoreMotion)
        motionManager?.stopAccelerometerUpdates()
        #endif
    }
    
    /// Extends playback and sleep timer by the specified number of seconds (default: 300s / 5 minutes).
    public func extendSleepTimer(by additionalSeconds: TimeInterval = 300.0) {
        stopShakeToExtendDetection()
        
        if let current = sleepTimerRemaining, current > 0 {
            let total = current + additionalSeconds
            let mins = max(1, Int(round(total / 60.0)))
            setSleepTimer(.minutes(mins))
        } else {
            setSleepTimer(.minutes(5))
            resume()
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
        
        // Skip Forward
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.skipForward(by: skipEvent.interval)
            }
            return .success
        }
        
        // Skip Backward
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
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
        
        // Change Playback Rate (CarPlay & Lock Screen speed controls)
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.setPlaybackRate(rateEvent.playbackRate)
            }
            return .success
        }
        
        // Next Track / Chapter (CarPlay Next Button)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipToNextChapter()
            }
            return .success
        }
        
        // Previous Track / Chapter (CarPlay Previous Button)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipToPreviousChapter()
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
        
        // Refresh skip command intervals from preferences
        let fwd = skipForwardInterval
        let bwd = skipBackwardInterval
        MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [NSNumber(value: fwd)]
        MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [NSNumber(value: bwd)]
        
        var info: [String: Any] = [:]
        
        // Title: Priority: Chapter title > Multi-part Track title > Book title
        if !chapters.isEmpty, let chapter = currentChapter {
            info[MPMediaItemPropertyTitle] = "\(item.title) — \(chapter.title)"
        } else if item.kind == .multiPart, let track = currentTrack {
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
        
        NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: self)
    }
    
    // MARK: - System Notifications
    
    #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
    private func handleAudioInterruption(typeValue: UInt, optionsValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                pause()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                resume()
            }
            wasPlayingBeforeInterruption = false
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
    
    // MARK: - SwiftUI Preview Mock
    
    /// Creates a mock AudioPlayerManager pre-populated with sample chapters and playback state.
    public static func previewMock() -> AudioPlayerManager {
        let player = AudioPlayerManager()
        let book = LibraryItem(
            title: "The Most Dangerous Games",
            author: "James Patterson",
            kind: .singleFile,
            totalDuration: 21600.0,
            currentPosition: 12030.0
        )
        player.currentItem = book
        player.currentTime = 12030.0
        player.totalDuration = 21600.0
        player.chapters = [
            ChapterInfo(index: 31, title: "Chapter 32", startTime: 10182.0, duration: 149.0),
            ChapterInfo(index: 32, title: "Game #2: Somewhere in Kentucky, Four Days Later", startTime: 10331.0, duration: 35.0),
            ChapterInfo(index: 33, title: "Chapter 33", startTime: 10367.0, duration: 423.0),
            ChapterInfo(index: 34, title: "Chapter 34", startTime: 10791.0, duration: 417.0),
            ChapterInfo(index: 35, title: "Chapter 35", startTime: 11209.0, duration: 135.0),
            ChapterInfo(index: 36, title: "Chapter 36", startTime: 11345.0, duration: 346.0),
            ChapterInfo(index: 37, title: "Chapter 37", startTime: 11692.0, duration: 586.0),
            ChapterInfo(index: 38, title: "Chapter 38", startTime: 12279.0, duration: 151.0),
            ChapterInfo(index: 39, title: "Chapter 39", startTime: 12430.0, duration: 254.0),
            ChapterInfo(index: 40, title: "Chapter 40", startTime: 12684.0, duration: 315.0),
            ChapterInfo(index: 41, title: "Chapter 41", startTime: 12999.0, duration: 293.0),
            ChapterInfo(index: 42, title: "Chapter 42", startTime: 13292.0, duration: 306.0),
            ChapterInfo(index: 43, title: "Chapter 43", startTime: 13598.0, duration: 355.0),
        ]
        return player
    }
}

// MARK: - Cross-Platform Image Typealias

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif
