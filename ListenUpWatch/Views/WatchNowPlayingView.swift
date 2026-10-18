import SwiftUI

/// Active playback source mode on Apple Watch.
public enum WatchPlayerMode: String, CaseIterable, Identifiable {
    case phoneRemote = "Phone"
    case watchLocal = "Watch"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .phoneRemote: return "iphone"
        case .watchLocal: return "applewatch"
        }
    }
}

/// Compact, watch-tailored audio player view.
/// Seamlessly controls iPhone playback (Remote Mode) or plays downloaded books locally (Standalone Mode).
/// Features Digital Crown scrubbing and chapter selection sheets.
public struct WatchNowPlayingView: View {
    @Environment(WatchSyncManager.self) private var syncManager
    @Environment(WatchAudioPlayerManager.self) private var localPlayer
    @Environment(WatchLibraryStore.self) private var libraryStore
    
    public var onNavigateToLibrary: (() -> Void)?
    
    @State private var playerMode: WatchPlayerMode = .phoneRemote
    @State private var crownScrubOffset: Double = 0.0
    @State private var showingChaptersSheet: Bool = false
    
    private let playbackRates: [Float] = PlaybackSpeed.supportedRates
    
    private func nextPlaybackRate(after current: Float) -> Float {
        if let idx = playbackRates.firstIndex(where: { abs($0 - current) < 0.05 }) {
            let nextIndex = (idx + 1) % playbackRates.count
            return playbackRates[nextIndex]
        }
        return PlaybackSpeed.defaultRate
    }
    
    public init(onNavigateToLibrary: (() -> Void)? = nil) {
        self.onNavigateToLibrary = onNavigateToLibrary
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Mode Toggle Header (Phone Remote vs Watch Standalone)
                modeSelectorHeader
                
                if playerMode == .phoneRemote {
                    phoneRemotePlayerContent
                } else {
                    watchLocalPlayerContent
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        #if os(watchOS)
        .focusable()
        .digitalCrownRotation(
            $crownScrubOffset,
            from: -100000.0,
            through: 100000.0,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownScrubOffset) { oldValue, newValue in
            let delta = newValue - oldValue
            guard abs(delta) >= 2.0 else { return }
            if playerMode == .phoneRemote {
                if delta > 0 {
                    syncManager.sendRemoteCommand(WatchRemoteCommand(type: .skipForward, value: abs(delta)))
                } else {
                    syncManager.sendRemoteCommand(WatchRemoteCommand(type: .skipBackward, value: abs(delta)))
                }
            } else {
                if delta > 0 {
                    localPlayer.skipForward(by: abs(delta))
                } else {
                    localPlayer.skipBackward(by: abs(delta))
                }
            }
        }
        #endif
        .sheet(isPresented: $showingChaptersSheet) {
            watchChaptersSheetContent
        }
    }
    
    // MARK: - Mode Selector Header
    
    private var modeSelectorHeader: some View {
        HStack(spacing: 6) {
            ForEach(WatchPlayerMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerMode = mode
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 10, weight: .bold))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        playerMode == mode
                            ? Color.accentColor.opacity(0.85)
                            : Color.white.opacity(0.12)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }
    
    // MARK: - Phone Remote Mode Content
    
    @ViewBuilder
    private var phoneRemotePlayerContent: some View {
        if let state = syncManager.remotePlaybackState, !state.title.isEmpty {
            VStack(spacing: 6) {
                // Title & Author
                VStack(spacing: 1) {
                    Text(state.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    
                    if let chapter = state.chapterTitle, !chapter.isEmpty {
                        Text(chapter)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    } else if let author = state.author, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Progress Bar & Timestamps
                VStack(spacing: 2) {
                    ProgressView(value: min(max(state.currentTime, 0.0), max(state.totalDuration, 1.0)), total: max(state.totalDuration, 1.0))
                        .tint(Color.accentColor)
                    
                    HStack {
                        Text(TimeFormatting.formatTimestamp(state.currentTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("-" + TimeFormatting.formatTimestamp(max(0.0, state.totalDuration - state.currentTime)))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                
                // Playback Controls (-15s, Play/Pause, +30s)
                HStack(spacing: 14) {
                    // Skip Backward 15s
                    Button {
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .skipBackward, value: 15.0))
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    // Main Play/Pause Button
                    Button {
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .togglePlayPause))
                    } label: {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.black)
                            .frame(width: 50, height: 50)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    // Skip Forward 30s
                    Button {
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .skipForward, value: 30.0))
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 20))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                
                // Secondary Controls: Prev Chapter, Speed, Chapters List, Next Chapter
                HStack(spacing: 8) {
                    // Previous Chapter
                    Button {
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .previousChapter))
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    // Speed Cycling Button
                    Button {
                        let next = nextPlaybackRate(after: state.playbackRate)
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .setPlaybackRate, value: Double(next)))
                    } label: {
                        Text(String(format: "%.2fx", state.playbackRate))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // Chapters List Button
                    Button {
                        showingChaptersSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10, weight: .semibold))
                            if !state.chapters.isEmpty {
                                Text("\(state.chapters.count)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // Next Chapter
                    Button {
                        syncManager.sendRemoteCommand(WatchRemoteCommand(type: .nextChapter))
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                
                // Pocket Indicator Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(syncManager.isReachable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(syncManager.isReachable ? "Connected to iPhone" : "Waiting for iPhone")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        } else {
            emptyPhoneRemotePlaceholder
        }
    }
    
    private var emptyPhoneRemotePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .padding(.top, 8)
            
            Text("No Active iPhone Audio")
                .font(.system(size: 13, weight: .semibold))
            
            Text("Start listening on your iPhone, or browse your library to select a book.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                onNavigateToLibrary?()
            } label: {
                Label("Open Library", systemImage: "books.vertical.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Watch Local Mode Content
    
    @ViewBuilder
    private var watchLocalPlayerContent: some View {
        if let _ = localPlayer.currentBookID, !localPlayer.currentBookTitle.isEmpty {
            VStack(spacing: 6) {
                // Title & Author
                VStack(spacing: 1) {
                    Text(localPlayer.currentBookTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    
                    if let author = localPlayer.currentBookAuthor, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Progress Bar & Timestamps
                VStack(spacing: 2) {
                    ProgressView(
                        value: min(max(localPlayer.currentTime, 0.0), max(localPlayer.totalDuration, 1.0)),
                        total: max(localPlayer.totalDuration, 1.0)
                    )
                    .tint(Color.green)
                    
                    HStack {
                        Text(TimeFormatting.formatTimestamp(localPlayer.currentTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("-" + TimeFormatting.formatTimestamp(max(0.0, localPlayer.totalDuration - localPlayer.currentTime)))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                
                // Controls (-15s, Play/Pause, +30s)
                HStack(spacing: 14) {
                    Button {
                        localPlayer.skipBackward(by: 15.0)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        localPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: localPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.black)
                            .frame(width: 50, height: 50)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        localPlayer.skipForward(by: 30.0)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 20))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                
                // Secondary Controls: Speed & Chapters
                HStack(spacing: 10) {
                    // Speed Cycling Button
                    Button {
                        let next = nextPlaybackRate(after: localPlayer.playbackRate)
                        localPlayer.setPlaybackRate(next)
                    } label: {
                        Text(String(format: "%.2fx", localPlayer.playbackRate))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // Chapters List Button
                    Button {
                        showingChaptersSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10, weight: .semibold))
                            if !localPlayer.chapters.isEmpty {
                                Text("\(localPlayer.chapters.count)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color.green)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                
                // Local Badge
                HStack(spacing: 4) {
                    Image(systemName: "applewatch.side.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Playing from Apple Watch")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        } else {
            emptyWatchLocalPlaceholder
        }
    }
    
    private var emptyWatchLocalPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "applewatch")
                .font(.system(size: 32))
                .foregroundStyle(Color.green.opacity(0.8))
                .padding(.top, 8)
            
            Text("No Local Book Playing")
                .font(.system(size: 13, weight: .semibold))
            
            Text("Download audiobooks to your Watch from the library to listen offline without your phone.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                onNavigateToLibrary?()
            } label: {
                Label("Browse Library", systemImage: "books.vertical.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.green)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Watch Chapters Sheet
    
    @ViewBuilder
    private var watchChaptersSheetContent: some View {
        let (chapters, currentTime): ([WatchChapterSummary], Double) = {
            if playerMode == .phoneRemote {
                let list = syncManager.remotePlaybackState?.chapters ?? []
                let time = syncManager.remotePlaybackState?.currentTime ?? 0.0
                return (list, time)
            } else {
                let list = localPlayer.chapters.map {
                    WatchChapterSummary(id: "\($0.id)", title: $0.title, startTime: $0.startTime, duration: $0.duration)
                }
                return (list, localPlayer.currentTime)
            }
        }()
        
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("No Chapters")
                            .font(.system(size: 13, weight: .bold))
                        Text("No embedded chapter markers were found for this audiobook.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(chapters) { chapter in
                            Button {
                                if playerMode == .phoneRemote {
                                    syncManager.sendRemoteCommand(WatchRemoteCommand(type: .seek, value: chapter.startTime))
                                } else {
                                    localPlayer.seek(to: chapter.startTime)
                                }
                                showingChaptersSheet = false
                            } label: {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(2)
                                        Text(TimeFormatting.formatChapterTimestamp(chapter.startTime))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if currentTime >= chapter.startTime && currentTime < (chapter.startTime + max(chapter.duration, 1.0)) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(playerMode == .phoneRemote ? Color.accentColor : Color.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingChaptersSheet = false
                    }
                }
            }
        }
    }
}

#Preview {
    WatchNowPlayingView()
        .environment(WatchSyncManager.shared)
        .environment(WatchAudioPlayerManager.shared)
        .environment(WatchLibraryStore.shared)
}
