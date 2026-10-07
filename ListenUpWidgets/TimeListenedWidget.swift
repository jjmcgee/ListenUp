import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

public struct TimeListenedTimelineProvider: TimelineProvider {
    public typealias Entry = TimeListenedEntry
    
    public init() {}
    
    public func placeholder(in context: Context) -> TimeListenedEntry {
        TimeListenedEntry(date: Date(), stats: WidgetStatsSnapshot.preview)
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (TimeListenedEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let snapshot = WidgetDataStore.shared.loadSnapshot()
        let entry = TimeListenedEntry(date: Date(), stats: snapshot.stats)
        completion(entry)
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<TimeListenedEntry>) -> Void) {
        let snapshot = WidgetDataStore.shared.loadSnapshot()
        let entry = TimeListenedEntry(date: Date(), stats: snapshot.stats)
        
        // Refresh every 30 minutes, or at midnight
        let calendar = Calendar.current
        let nextUpdate: Date
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
           let tomorrowMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) {
            let halfHour = Date().addingTimeInterval(1800)
            nextUpdate = min(tomorrowMidnight, halfHour)
        } else {
            nextUpdate = Date().addingTimeInterval(1800)
        }
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

public struct TimeListenedEntry: TimelineEntry {
    public let date: Date
    public let stats: WidgetStatsSnapshot
    
    public init(date: Date, stats: WidgetStatsSnapshot) {
        self.date = date
        self.stats = stats
    }
}

// MARK: - Main Entry View

public struct TimeListenedEntryView: View {
    @Environment(\.widgetFamily) private var family
    public var entry: TimeListenedEntry
    
    public init(entry: TimeListenedEntry) {
        self.entry = entry
    }
    
    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallTimeListenedView(stats: entry.stats)
            case .systemMedium:
                MediumTimeListenedView(stats: entry.stats)
            default:
                SmallTimeListenedView(stats: entry.stats)
            }
        }
        .containerBackground(for: .widget) {
            widgetBackdrop
        }
        .widgetURL(URL(string: "listenup://stats"))
    }
    
    private var widgetBackdrop: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
            
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.16),
                    Color.accentColor.opacity(0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Small Time Listened View

public struct SmallTimeListenedView: View {
    public let stats: WidgetStatsSnapshot
    
    public init(stats: WidgetStatsSnapshot) {
        self.stats = stats
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Label("Today", systemImage: "clock.badge.waveform")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if stats.streakDays > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.orange)
                        Text("\(stats.streakDays)d")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                }
            }
            
            Spacer(minLength: 0)
            
            // Central Ring & Big Time Display
            HStack(spacing: 12) {
                // Circular Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 5)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(stats.goalProgressFraction))
                        .stroke(
                            stats.isGoalAccomplished ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    
                    Text(stats.goalPercentageText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.todayFormatted)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Goal: \(stats.goalMinutes)m")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            // Footer status
            HStack {
                if stats.isGoalAccomplished {
                    Label("Goal Met!", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                } else {
                    Text("\(stats.remainingMinutes)m to reach goal")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
        }
    }
}

// MARK: - Medium Time Listened View

public struct MediumTimeListenedView: View {
    public let stats: WidgetStatsSnapshot
    
    public init(stats: WidgetStatsSnapshot) {
        self.stats = stats
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Left Card: Today's Goal Ring & Time
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Today", systemImage: "chart.bar.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if stats.streakDays > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.orange)
                            Text("\(stats.streakDays)d")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }
                
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 5)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(stats.goalProgressFraction))
                            .stroke(
                                stats.isGoalAccomplished ? Color.green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text(stats.goalPercentageText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stats.todayFormatted)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("of \(stats.goalMinutes)m daily goal")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Progress status pill
                HStack(spacing: 4) {
                    Image(systemName: stats.isGoalAccomplished ? "checkmark.circle.fill" : "arrow.up.forward.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(stats.isGoalAccomplished ? Color.green : Color.accentColor)
                    
                    Text(stats.isGoalAccomplished ? "Goal Accomplished!" : "\(stats.remainingMinutes) min remaining")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(stats.isGoalAccomplished ? Color.green : .white.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)
            
            // Right Card: Monthly & Lifetime Breakdown
            VStack(alignment: .leading, spacing: 8) {
                // Monthly section
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Monthly")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if let pct = stats.monthPercentageChange, !pct.isNaN {
                            HStack(spacing: 2) {
                                Image(systemName: pct >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                Text(String(format: "%.0f%%", abs(pct)))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(pct >= 0 ? Color.green : Color.red)
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f hrs", stats.currentMonthHours))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        if !stats.previousMonthName.isEmpty {
                            Text("vs \(String(format: "%.1fh", stats.previousMonthHours)) in \(stats.previousMonthName)")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Lifetime total section
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Listened")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text(stats.totalSummaryFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget Declaration

public struct TimeListenedWidget: Widget {
    public let kind: String = "ListenUpTimeListenedWidget"
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeListenedTimelineProvider()) { entry in
            TimeListenedEntryView(entry: entry)
        }
        .configurationDisplayName("Time Listened")
        .description("Track your daily listening goal progress and monthly statistics.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small Time Listened", as: .systemSmall) {
    TimeListenedWidget()
} timeline: {
    TimeListenedEntry(date: Date(), stats: WidgetStatsSnapshot.preview)
}

#Preview("Medium Time Listened", as: .systemMedium) {
    TimeListenedWidget()
} timeline: {
    TimeListenedEntry(date: Date(), stats: WidgetStatsSnapshot.preview)
}
