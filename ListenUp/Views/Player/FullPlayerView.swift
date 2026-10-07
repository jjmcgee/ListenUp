import SwiftUI

/// Full-screen audio player presentation modal.
/// Includes large artwork, precise interactive scrubber, skip controls (-15s/+30s),
/// speed controls, sleep timer, and track breakdown for multi-part books.
public struct FullPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    @AppStorage("skipForwardInterval") private var skipForwardInterval: Double = 30.0
    @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Double = 15.0
    
    @State private var sliderValue: Double = 0.0
    @State private var isDraggingSlider: Bool = false
    @State private var isShowingBookScrubber: Bool = false
    @State private var activeScrubbingChapter: ChapterInfo? = nil
    @State private var showingSleepTimerSheet: Bool = false
    @State private var showingChaptersSheet: Bool = false
    @State private var showingWatchSyncSheet: Bool = false
    
    private var skipBackwardIcon: String {
        let seconds = Int(skipBackwardInterval)
        switch seconds {
        case 5, 10, 15, 30, 45, 60, 75, 90:
            return "gobackward.\(seconds)"
        default:
            return "gobackward"
        }
    }
    
    private var skipForwardIcon: String {
        let seconds = Int(skipForwardInterval)
        switch seconds {
        case 5, 10, 15, 30, 45, 60, 75, 90:
            return "goforward.\(seconds)"
        default:
            return "goforward"
        }
    }
    
    public init(player: AudioPlayerManager) {
        self.player = player
    }
    
    public var body: some View {
        guard let item = player.currentItem else {
            return AnyView(
                VStack {
                    Text("No Audiobook Loaded")
                        .foregroundStyle(Color.secondary)
                }
            )
        }
        
        return AnyView(
            NavigationStack {
                ZStack {
                    LiquidGlassMeshBackground(
                        primaryColor: Color.accentColor,
                        secondaryColor: Color.purple
                    )
                    
                    GeometryReader { geometry in
                        let hasChapters = !player.chapters.isEmpty
                        let isChapterMode = hasChapters && !isShowingBookScrubber
                        let activeChapter = activeScrubbingChapter ?? player.currentChapter
                        
                        let scrubberMaxDuration: Double = {
                            if isChapterMode, let ch = activeChapter {
                                return max(ch.duration, 1.0)
                            } else {
                                return max(player.totalDuration, 1.0)
                            }
                        }()
                        
                        let currentScrubberDisplayValue: Double = {
                            if isDraggingSlider {
                                return sliderValue
                            }
                            if isChapterMode {
                                return player.currentChapterElapsed
                            } else {
                                return player.currentTime
                            }
                        }()
                        
                        VStack(spacing: 16) {
                            
                            // Top Drag Indicator / Header
                            HStack {
                                Button {
                                    dismiss()
                                } label: {
                                    Image(systemName: "chevron.compact.down")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(Color.secondary)
                                        .frame(width: 40, height: 40)
                                        .liquidGlassCircle(isInteractive: true)
                                }
                                
                                Spacer()
                                
                                Button {
                                    showingWatchSyncSheet = true
                                } label: {
                                    Image(systemName: "applewatch.radiowaves.left.and.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 40, height: 40)
                                        .liquidGlassCircle(tint: Color.accentColor, isInteractive: true)
                                }
                                .accessibilityLabel("Apple Watch Sync")
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        
                        Spacer(minLength: 4)
                        
                        // Large Artwork Cover with Deep Shadow
                        let artworkWidth = max(0.0, geometry.size.width - 64)
                        let artworkHeight = max(0.0, geometry.size.height * 0.34)
                        let artworkSize = max(50.0, min(artworkWidth, artworkHeight))
                        ArtworkImageView(
                            artworkData: item.artworkData,
                            title: item.title,
                            kind: item.kind,
                            cornerRadius: 16
                        )
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
                        
                        Spacer(minLength: 4)
                        
                        // Titles & Author
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 24)
                            
                            if let author = item.author, !author.isEmpty {
                                Text(author)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        // Chapter Navigation Header (< Chapter Title >)
                        if hasChapters, let currentChapter = player.currentChapter {
                            HStack {
                                // Skip Previous Chapter
                                Button {
                                    player.skipToPreviousChapter()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.primary)
                                        .frame(width: 36, height: 36)
                                        .liquidGlassCircle(isInteractive: true)
                                }
                                .disabled(player.currentChapterIndex == 0 && player.currentChapterElapsed <= 3.0)
                                .opacity((player.currentChapterIndex == 0 && player.currentChapterElapsed <= 3.0) ? 0.35 : 1.0)
                                
                                Spacer()
                                
                                // Chapter Title (tap opens chapters sheet)
                                Button {
                                    showingChaptersSheet = true
                                } label: {
                                    Text(currentChapter.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .liquidGlassCapsule(tint: Color.accentColor, isInteractive: true)
                                }
                                
                                Spacer()
                                
                                // Skip Next Chapter
                                Button {
                                    player.skipToNextChapter()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.primary)
                                        .frame(width: 36, height: 36)
                                        .liquidGlassCircle(isInteractive: true)
                                }
                                .disabled(player.currentChapterIndex == (player.chapters.count - 1))
                                .opacity((player.currentChapterIndex == (player.chapters.count - 1)) ? 0.35 : 1.0)
                            }
                            .padding(.horizontal, 20)
                        } else if item.kind == .multiPart, let currentTrack = player.currentTrack {
                            Text("Part \(player.currentTrackIndex + 1) of \(item.playableTracks.count) — \(currentTrack.title)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }
                        
                        // Interactive Scrubber & Timeline
                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: {
                                        currentScrubberDisplayValue
                                    },
                                    set: { newValue in
                                        sliderValue = newValue
                                        if !isDraggingSlider {
                                            isDraggingSlider = true
                                            activeScrubbingChapter = player.currentChapter
                                            player.startScrubbing()
                                        }
                                        if isChapterMode, let ch = activeScrubbingChapter ?? player.currentChapter {
                                            let targetTime = min(max(ch.startTime + newValue, ch.startTime), ch.endTime)
                                            player.scrubUpdate(to: targetTime)
                                        } else {
                                            player.scrubUpdate(to: newValue)
                                        }
                                    }
                                ),
                                in: 0...scrubberMaxDuration,
                                onEditingChanged: { isEditing in
                                    if isEditing {
                                        isDraggingSlider = true
                                        activeScrubbingChapter = player.currentChapter
                                        sliderValue = isChapterMode ? player.currentChapterElapsed : player.currentTime
                                        player.startScrubbing()
                                    } else {
                                        if isChapterMode, let ch = activeScrubbingChapter ?? player.currentChapter {
                                            let targetTime = min(max(ch.startTime + sliderValue, ch.startTime), ch.endTime)
                                            player.endScrubbing(to: targetTime)
                                        } else {
                                            player.endScrubbing(to: sliderValue)
                                        }
                                        isDraggingSlider = false
                                        activeScrubbingChapter = nil
                                    }
                                }
                            )
                            .tint(Color.accentColor)
                            
                            // Time Labels (05:38 - Chapter 44 of 136 - -04:08)
                            HStack {
                                // Left: Elapsed Time
                                Text(
                                    isChapterMode
                                        ? TimeFormatting.formatChapterDuration(isDraggingSlider ? sliderValue : player.currentChapterElapsed)
                                        : TimeFormatting.formatTimestamp(isDraggingSlider ? sliderValue : player.currentTime)
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                
                                Spacer()
                                
                                // Center: Chapter X of Y
                                if let ch = activeChapter, hasChapters {
                                    Text("Chapter \(ch.index + 1) of \(player.chapters.count)")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(Color.secondary)
                                    
                                    Spacer()
                                } else if item.kind == .multiPart {
                                    Text("Part \(player.currentTrackIndex + 1) of \(item.playableTracks.count)")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(Color.secondary)
                                    
                                    Spacer()
                                }
                                
                                // Right: Remaining Time
                                Text(
                                    isChapterMode
                                        ? TimeFormatting.formatChapterRemaining(
                                            isDraggingSlider
                                                ? max(0.0, (activeChapter?.duration ?? 0.0) - sliderValue)
                                                : player.currentChapterRemaining
                                        )
                                        : TimeFormatting.formatRemainingTimestamp(
                                            current: isDraggingSlider ? sliderValue : player.currentTime,
                                            total: player.totalDuration
                                        )
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                            }
                            
                            // Book Remaining Indicator & Scrubber Mode Toggle
                            let bookRemainingSeconds = max(0.0, player.totalDuration - player.currentTime)
                            let bookRemainingFormatted = TimeFormatting.formatVerbalDuration(bookRemainingSeconds)
                            
                            if hasChapters {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isShowingBookScrubber.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isShowingBookScrubber ? "list.bullet" : "book.closed")
                                            .font(.system(size: 11, weight: .medium))
                                        
                                        if isShowingBookScrubber {
                                            Text("Full Book Timeline (\(bookRemainingFormatted) left)")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        } else {
                                            Text("\(bookRemainingFormatted) left in book")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                        
                                        Image(systemName: "arrow.left.arrow.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .liquidGlassCapsule(tint: isShowingBookScrubber ? Color.accentColor : nil, isInteractive: true)
                                    .foregroundStyle(Color.primary)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 5) {
                                    Image(systemName: "book.closed")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("\(bookRemainingFormatted) left in book")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .liquidGlassCapsule()
                                .foregroundStyle(Color.secondary)
                                .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Primary Playback Controls
                        HStack(spacing: 32) {
                            // Skip Backward
                            Button {
                                player.skipBackward(by: skipBackwardInterval)
                            } label: {
                                Image(systemName: skipBackwardIcon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 56, height: 56)
                                    .liquidGlassCircle(isInteractive: true)
                            }
                            
                            // Play / Pause Toggle
                            Button {
                                player.togglePlayPause()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 74))
                                    .foregroundStyle(Color.accentColor)
                                    .shadow(color: Color.accentColor.opacity(0.35), radius: 14, x: 0, y: 6)
                            }
                            
                            // Skip Forward
                            Button {
                                player.skipForward(by: skipForwardInterval)
                            } label: {
                                Image(systemName: skipForwardIcon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 56, height: 56)
                                    .liquidGlassCircle(isInteractive: true)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Secondary Toolbar: Speed, Sleep Timer & Chapters
                        HStack(spacing: 12) {
                            PlaybackSpeedMenu(player: player)
                            
                            Spacer()
                            
                            // Sleep Timer Button
                            Button {
                                showingSleepTimerSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: player.activeSleepTimerOption == .off ? "timer" : "timer.circle.fill")
                                        .font(.system(size: 15))
                                    
                                    if let remaining = player.sleepTimerRemaining, player.activeSleepTimerOption != .off {
                                        Text(TimeFormatting.formatTimestamp(remaining))
                                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    } else {
                                        Text("Timer")
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .liquidGlassCapsule(tint: player.activeSleepTimerOption == .off ? nil : Color.accentColor, isInteractive: true)
                                .foregroundStyle(player.activeSleepTimerOption == .off ? Color.primary : Color.accentColor)
                            }
                            
                            // Chapters List Button (Icon 4 placed after timer icon as requested)
                            Button {
                                showingChaptersSheet = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 36, height: 36)
                                    .liquidGlassCircle(isInteractive: true)
                            }
                            .accessibilityLabel("Chapters")
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                }
                }
                .sheet(isPresented: $showingSleepTimerSheet) {
                    SleepTimerSheet(player: player)
                }
                .sheet(isPresented: $showingChaptersSheet) {
                    ChaptersSheet(player: player)
                }
                .sheet(isPresented: $showingWatchSyncSheet) {
                    WatchSyncSheet(item: player.currentItem)
                }
            }
        )
    }
}

#Preview("Full Player Screen") {
    FullPlayerView(player: .previewMock())
}


