import Foundation

/// Utilities for formatting audio playback durations and timestamps into human-readable strings.
public enum TimeFormatting {
    
    /// Formats seconds into a standard audio timestamp like `mm:ss` or `hh:mm:ss`.
    /// Example: `75` -> `"1:15"`, `3665` -> `"1:01:05"`
    public static func formatTimestamp(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else {
            return "0:00"
        }
        
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    /// Formats remaining seconds as a countdown timestamp prefixed with minus.
    /// Example: `125` -> `"-2:05"`
    public static func formatRemainingTimestamp(current: Double, total: Double) -> String {
        let remaining = max(0, total - current)
        return "-\(formatTimestamp(remaining))"
    }
    
    /// Formats a duration into a verbalized duration (e.g., "1 hr 45 min" or "42 min").
    public static func formatVerbalDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else {
            return "0 min"
        }
        
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours) hr \(minutes) min"
        } else if hours > 0 {
            return "\(hours) hr"
        } else {
            return "\(max(1, minutes)) min"
        }
    }
}
