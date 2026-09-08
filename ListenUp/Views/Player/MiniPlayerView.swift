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
                GeometryReader { geo in
                    let progressFraction = player.totalDuration > 0
                        ? min(max(player.currentTime / player.totalDuration, 0.0), 1.0)
                        : 0.0
                    
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(progressFraction))
                    }
                }
                .frame(height: 2.5)
                
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
                            .font(.system(size: 22))
                            .foregroundStyle(Color.primary)
                            .frame(width: 32, height: 32)
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onExpand()
            }
        }
    }
}
