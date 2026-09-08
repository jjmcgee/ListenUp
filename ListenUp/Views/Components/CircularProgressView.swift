import SwiftUI

/// Elegant circular progress indicator displaying media completion percentage.
public struct CircularProgressView: View {
    public let progress: Double
    public var strokeWidth: CGFloat = 3.5
    public var ringColor: Color = .accentColor
    public var trackColor: Color = Color.secondary.opacity(0.2)
    
    public init(
        progress: Double,
        strokeWidth: CGFloat = 3.5,
        ringColor: Color = .accentColor,
        trackColor: Color = Color.secondary.opacity(0.2)
    ) {
        self.progress = progress
        self.strokeWidth = strokeWidth
        self.ringColor = ringColor
        self.trackColor = trackColor
    }
    
    public var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)
            
            // Progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(min(max(progress, 0.0), 1.0)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CircularProgressView(progress: 0.35)
            .frame(width: 32, height: 32)
        
        CircularProgressView(progress: 0.75, ringColor: .orange)
            .frame(width: 48, height: 48)
    }
    .padding()
}
