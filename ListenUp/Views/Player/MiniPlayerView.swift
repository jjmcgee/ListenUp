import SwiftUI

/// Floating mini-player pinned above the bottom bar.
/// Offers quick playback controls, current scrub progress, and expands to full screen on tap.
public struct MiniPlayerView: View {
    var player: AudioPlayerManager
    public var onExpand: () -> Void
    
    public init(player: AudioPlayerManager, onExpand: @escaping () -> Void) {
        self.player = player
        self.onExpand = onExpand
    }
    
    public var body: some View {
        if let item = player.currentItem {
            VStack(spacing: 0) {
                // Top Mini Scrub Progress Line
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    
                    GeometryReader { geo in
                        let progressFraction = player.totalDuration > 0
                            ? min(max(player.currentTime / player.totalDuration, 0.0), 1.0)
                            : 0.0
                        
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: max(0.0, geo.size.width * CGFloat(progressFraction)))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 2.5)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                
                HStack(spacing: 12) {
                    // Artwork Thumbnail
                    ArtworkImageView(
                        artworkData: item.artworkData,
                        title: item.title,
                        kind: item.kind,
                        cornerRadius: 6
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(Color.primary)
                        
                        Text(item.author ?? (item.kind == .multiPart ? (player.currentTrack?.title ?? "Multi-part") : "Audiobook"))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Controls: Skip Backward (15s)
                    Button {
                        player.skipBackward(by: 15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 4)
                    
                    // Controls: Play / Pause
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .liquidGlassCircle(tint: Color.accentColor, isInteractive: true)
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .liquidGlass(cornerRadius: 18, tint: Color.accentColor)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {
                onExpand()
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview("Mini Player") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        MiniPlayerView(player: .previewMock()) {}
            .padding(.bottom, 20)
    }
}
