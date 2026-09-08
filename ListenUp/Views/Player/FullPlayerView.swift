import SwiftUI

/// Full-screen audio player presentation modal.
/// Includes large artwork, precise interactive scrubber, skip controls (-15s/+30s),
/// speed controls, sleep timer, and track breakdown for multi-part books.
public struct FullPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    @State private var sliderValue: Double = 0.0
    @State private var isDraggingSlider: Bool = false
    @State private var showingSleepTimerSheet: Bool = false
    @State private var showingTrackListSheet: Bool = false
    
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
                GeometryReader { geometry in
                    VStack(spacing: 20) {
                        
                        // Top Drag Indicator / Header
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.compact.down")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                            }
                            
                            Spacer()
                            
                            if item.kind == .multiPart {
                                Button {
                                    showingTrackListSheet = true
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.primary)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        
                        Spacer(minLength: 8)
                        
                        // Large Artwork Cover with Deep Shadow
                        let artworkSize = min(geometry.size.width - 64, geometry.size.height * 0.38)
                        ArtworkImageView(
                            artworkData: item.artworkData,
                            title: item.title,
                            kind: item.kind,
                            cornerRadius: 16
                        )
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
                        
                        Spacer(minLength: 8)
                        
                        // Titles & Part Subtitle
                        VStack(spacing: 6) {
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
                            
                            // Multi-part Track / Chapter Indicator
                            if item.kind == .multiPart, let currentTrack = player.currentTrack {
                                Text("Part \(player.currentTrackIndex + 1) of \(item.playableTracks.count) — \(currentTrack.title)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.top, 2)
                            }
                        }
                        
                        // Interactive Scrubber
                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: {
                                        isDraggingSlider ? sliderValue : player.currentTime
                                    },
                                    set: { newValue in
                                        sliderValue = newValue
                                        if !isDraggingSlider {
                                            player.startScrubbing()
                                            isDraggingSlider = true
                                        }
                                        player.scrubUpdate(to: newValue)
                                    }
                                ),
                                in: 0...max(player.totalDuration, 1.0),
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        player.endScrubbing(to: sliderValue)
                                        isDraggingSlider = false
                                    }
                                }
                            )
                            .tint(Color.accentColor)
                            
                            // Time Labels
                            HStack {
                                Text(TimeFormatting.formatTimestamp(isDraggingSlider ? sliderValue : player.currentTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                
                                Spacer()
                                
                                Text(TimeFormatting.formatRemainingTimestamp(
                                    current: isDraggingSlider ? sliderValue : player.currentTime,
                                    total: player.totalDuration
                                ))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Primary Playback Controls
                        HStack(spacing: 36) {
                            // Skip Backward 15s
                            Button {
                                player.skipBackward(by: 15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.primary)
                            }
                            
                            // Play / Pause Toggle
                            Button {
                                player.togglePlayPause()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 72))
                                    .foregroundStyle(Color.accentColor)
                            }
                            
                            // Skip Forward 30s
                            Button {
                                player.skipForward(by: 30)
                            } label: {
                                Image(systemName: "goforward.30")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Secondary Toolbar: Speed & Sleep Timer
                        HStack {
                            PlaybackSpeedMenu(player: player)
                            
                            Spacer()
                            
                            // Sleep Timer Button
                            Button {
                                showingSleepTimerSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: player.activeSleepTimerOption == .off ? "timer" : "timer.circle.fill")
                                        .font(.system(size: 16))
                                    
                                    if let remaining = player.sleepTimerRemaining, player.activeSleepTimerOption != .off {
                                        Text(TimeFormatting.formatTimestamp(remaining))
                                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    } else {
                                        Text("Timer")
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(player.activeSleepTimerOption == .off ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundStyle(player.activeSleepTimerOption == .off ? Color.primary : Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    }
                }
                .sheet(isPresented: $showingSleepTimerSheet) {
                    SleepTimerSheet(player: player)
                }
                .sheet(isPresented: $showingTrackListSheet) {
                    TrackListSheet(player: player)
                }
            }
        )
    }
}

/// Sheet displaying ordered tracks inside a multi-part audiobook.
struct TrackListSheet: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    var body: some View {
        NavigationStack {
            List {
                if let item = player.currentItem {
                    let segments = item.segments
                    
                    ForEach(segments) { segment in
                        Button {
                            player.seek(to: segment.startVirtualTime)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(segment.track.title)
                                        .font(.headline)
                                        .foregroundStyle(segment.trackIndex == player.currentTrackIndex ? Color.accentColor : Color.primary)
                                    
                                    Text(TimeFormatting.formatTimestamp(segment.duration))
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Spacer()
                                
                                if segment.trackIndex == player.currentTrackIndex {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chapters & Parts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
