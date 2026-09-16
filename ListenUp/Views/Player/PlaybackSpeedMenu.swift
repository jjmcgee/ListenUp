import SwiftUI

/// Menu allowing granular selection of playback speed multipliers.
public struct PlaybackSpeedMenu: View {
    var player: AudioPlayerManager
    
    public static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5]
    
    public init(player: AudioPlayerManager) {
        self.player = player
    }
    
    public var body: some View {
        Menu {
            ForEach(Self.availableRates, id: \.self) { rate in
                Button {
                    player.setPlaybackRate(rate)
                } label: {
                    HStack {
                        Text(String(format: "%.2fx", rate))
                        if abs(player.playbackRate - rate) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(String(format: "%.2fx", player.playbackRate))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .liquidGlassCapsule(tint: Color.accentColor, isInteractive: true)
        }
    }
}
