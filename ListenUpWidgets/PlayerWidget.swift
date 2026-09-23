import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

public struct PlayerTimelineProvider: TimelineProvider {
    public typealias Entry = PlayerEntry
    
    public init() {}
    
    public func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(
            date: Date(),
            nowPlaying: WidgetPlaybackSnapshot.preview,
            recentBooks: WidgetRecentBook.previewList
        )
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (PlayerEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let snapshot = WidgetDataStore.shared.loadSnapshot()
        let entry = PlayerEntry(
            date: Date(),
            nowPlaying: snapshot.nowPlaying,
            recentBooks: snapshot.recentBooks
        )
        completion(entry)
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerEntry>) -> Void) {
        let snapshot = WidgetDataStore.shared.loadSnapshot()
        let entry = PlayerEntry(
            date: Date(),
            nowPlaying: snapshot.nowPlaying,
            recentBooks: snapshot.recentBooks
        )
        // Refresh every 15 minutes unless triggered earlier by main app updates
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

public struct PlayerEntry: TimelineEntry {
    public let date: Date
    public let nowPlaying: WidgetPlaybackSnapshot?
    public let recentBooks: [WidgetRecentBook]
    
    public init(date: Date, nowPlaying: WidgetPlaybackSnapshot?, recentBooks: [WidgetRecentBook]) {
        self.date = date
        self.nowPlaying = nowPlaying
        self.recentBooks = recentBooks
    }
}

// MARK: - Main Entry View

public struct PlayerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    public var entry: PlayerEntry
    
    public init(entry: PlayerEntry) {
        self.entry = entry
    }
    
    private var resolvedNowPlaying: WidgetPlaybackSnapshot? {
        if let current = entry.nowPlaying {
            return current
        }
        if let firstRecent = entry.recentBooks.first {
            return WidgetPlaybackSnapshot(
                bookID: firstRecent.id,
                title: firstRecent.title,
                author: firstRecent.author,
                currentTime: firstRecent.progress * firstRecent.totalDuration,
                totalDuration: firstRecent.totalDuration,
                progress: firstRecent.progress,
                isPlaying: false,
                artworkData: firstRecent.artworkData,
                lastUpdated: firstRecent.lastUpdated
            )
        }
        return nil
    }
    
    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallPlayerWidgetView(nowPlaying: resolvedNowPlaying)
            case .systemMedium:
                MediumPlayerWithRecentBooksView(
                    nowPlaying: resolvedNowPlaying,
                    recentBooks: entry.recentBooks
                )
            default:
                SmallPlayerWidgetView(nowPlaying: resolvedNowPlaying)
            }
        }
        .containerBackground(for: .widget) {
            widgetBackdrop
        }
    }
    
    private var widgetBackdrop: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
            
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.purple.opacity(0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Small Player View

public struct SmallPlayerWidgetView: View {
    public let nowPlaying: WidgetPlaybackSnapshot?
    
    public init(nowPlaying: WidgetPlaybackSnapshot?) {
        self.nowPlaying = nowPlaying
    }
    
    public var body: some View {
        if let book = nowPlaying {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Status badge & Play/Pause button
                HStack(alignment: .center) {
                    Label(book.isPlaying ? "Playing" : "Paused", systemImage: book.isPlaying ? "waveform" : "pause.circle")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(book.isPlaying ? Color.green : Color.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: book.isPlaying)
                    
                    Spacer()
                    
                    Button(intent: TogglePlaybackIntent()) {
                        Image(systemName: book.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Artwork & Title Info
                HStack(spacing: 8) {
                    artworkView(data: book.artworkData, title: book.title, size: 42)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(book.author)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Timeline progress bar & remaining time
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(4, geo.size.width * CGFloat(book.progress)), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    HStack {
                        Text(book.formattedCurrentPosition)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text(book.formattedRemaining)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .widgetURL(URL(string: "listenup://nowplaying"))
        } else {
            emptyStateView
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)
            
            Text("ListenUp")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("No Audiobook Playing\nTap to browse library")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "listenup://library"))
    }
}

// MARK: - Medium Player with Recent Books View

public struct MediumPlayerWithRecentBooksView: View {
    public let nowPlaying: WidgetPlaybackSnapshot?
    public let recentBooks: [WidgetRecentBook]
    
    public init(nowPlaying: WidgetPlaybackSnapshot?, recentBooks: [WidgetRecentBook]) {
        self.nowPlaying = nowPlaying
        self.recentBooks = recentBooks
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Left Card: Now Playing
            if let book = nowPlaying {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(book.isPlaying ? "Now Playing" : "Paused", systemImage: book.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(book.isPlaying ? Color.green : Color.secondary)
                        
                        Spacer()
                        
                        Button(intent: TogglePlaybackIntent()) {
                            Image(systemName: book.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 8) {
                        artworkView(data: book.artworkData, title: book.title, size: 48)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            
                            Text(book.author)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)
                                
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: max(4, geo.size.width * CGFloat(book.progress)), height: 4)
                            }
                        }
                        .frame(height: 4)
                        
                        HStack {
                            Text(book.formattedCurrentPosition)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(book.formattedRemaining)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                    Text("No Active Book")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Tap to browse")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Subtle Divider
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)
            
            // Right Card: Recent Books Shelf
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent Books")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                if recentBooks.isEmpty {
                    VStack {
                        Spacer()
                        Text("No recent audiobooks")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(recentBooks.prefix(3)) { book in
                            Link(destination: URL(string: "listenup://play?id=\(book.id.uuidString)")!) {
                                HStack(spacing: 8) {
                                    artworkView(data: book.artworkData, title: book.title, size: 28)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(book.title)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        
                                        Text(book.author)
                                            .font(.system(size: 9, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer(minLength: 0)
                                    
                                    // Progress Ring or Percentage
                                    Text(book.progressPercentageText)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "listenup://nowplaying"))
    }
}

// MARK: - Artwork View Helper

@ViewBuilder
private func artworkView(data: Data?, title: String, size: CGFloat) -> some View {
    if let data = data, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    } else {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(title.prefix(1).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Widget Declaration

public struct PlayerWidget: Widget {
    public let kind: String = "ListenUpPlayerWidget"
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayerTimelineProvider()) { entry in
            PlayerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ListenUp Player")
        .description("Control playback of your active audiobook or jump into recent books.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small Playing", as: .systemSmall) {
    PlayerWidget()
} timeline: {
    PlayerEntry(
        date: Date(),
        nowPlaying: WidgetPlaybackSnapshot.preview,
        recentBooks: WidgetRecentBook.previewList
    )
}

#Preview("Medium Player & Recents", as: .systemMedium) {
    PlayerWidget()
} timeline: {
    PlayerEntry(
        date: Date(),
        nowPlaying: WidgetPlaybackSnapshot.preview,
        recentBooks: WidgetRecentBook.previewList
    )
}

#Preview("Small Empty", as: .systemSmall) {
    PlayerWidget()
} timeline: {
    PlayerEntry(
        date: Date(),
        nowPlaying: nil,
        recentBooks: []
    )
}
