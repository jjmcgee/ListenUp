import Foundation

/// Unified Sendable & Codable snapshots for sharing data between ListenUp and its Widget extensions.
///
/// Designed to be lightweight and fast-deserializing, ensuring the widget stays well within
/// the strict 30MB extension memory ceiling.

// MARK: - Playback Snapshot

public struct WidgetPlaybackSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { bookID }
    public let bookID: UUID
    public let title: String
    public let author: String
    public let currentTime: Double
    public let totalDuration: Double
    public let progress: Double
    public let isPlaying: Bool
    public let artworkData: Data?
    public let lastUpdated: Date
    
    public init(
        bookID: UUID,
        title: String,
        author: String,
        currentTime: Double,
        totalDuration: Double,
        progress: Double,
        isPlaying: Bool,
        artworkData: Data?,
        lastUpdated: Date = Date()
    ) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.progress = min(max(progress, 0.0), 1.0)
        self.isPlaying = isPlaying
        self.artworkData = artworkData
        self.lastUpdated = lastUpdated
    }
    
    public var formattedCurrentPosition: String {
        let seconds = Int(currentTime)
        let mins = (seconds % 3600) / 60
        let hours = seconds / 3600
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
    
    public var formattedRemaining: String {
        let remaining = max(0.0, totalDuration - currentTime)
        let seconds = Int(remaining)
        let mins = (seconds % 3600) / 60
        let hours = seconds / 3600
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "-%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "-%d:%02d", mins, secs)
        }
    }
    
    public var progressPercentageText: String {
        "\(Int(progress * 100))%"
    }
}

// MARK: - Recent Book Item

public struct WidgetRecentBook: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let author: String
    public let progress: Double
    public let totalDuration: Double
    public let artworkData: Data?
    public let lastUpdated: Date
    
    public init(
        id: UUID,
        title: String,
        author: String,
        progress: Double,
        totalDuration: Double,
        artworkData: Data?,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.progress = min(max(progress, 0.0), 1.0)
        self.totalDuration = totalDuration
        self.artworkData = artworkData
        self.lastUpdated = lastUpdated
    }
    
    public var progressPercentageText: String {
        "\(Int(progress * 100))%"
    }
}

// MARK: - Statistics Snapshot

public struct WidgetStatsSnapshot: Codable, Sendable, Equatable {
    public let todaySeconds: Double
    public let todayHours: Int
    public let todayMinutes: Int
    public let todayFormatted: String
    public let goalMinutes: Int
    public let goalProgressFraction: Double
    public let goalPercentageText: String
    public let isGoalAccomplished: Bool
    public let remainingMinutes: Int
    
    public let currentMonthName: String
    public let currentMonthHours: Double
    public let previousMonthName: String
    public let previousMonthHours: Double
    public let monthDeltaHours: Double
    public let monthPercentageChange: Double?
    
    public let totalSummaryFormatted: String
    public let totalHours: Double
    public let streakDays: Int
    public let lastUpdated: Date
    
    public init(
        todaySeconds: Double = 0,
        todayHours: Int = 0,
        todayMinutes: Int = 0,
        todayFormatted: String = "0m",
        goalMinutes: Int = 30,
        goalProgressFraction: Double = 0.0,
        goalPercentageText: String = "0%",
        isGoalAccomplished: Bool = false,
        remainingMinutes: Int = 30,
        currentMonthName: String = "",
        currentMonthHours: Double = 0.0,
        previousMonthName: String = "",
        previousMonthHours: Double = 0.0,
        monthDeltaHours: Double = 0.0,
        monthPercentageChange: Double? = nil,
        totalSummaryFormatted: String = "0h 0m",
        totalHours: Double = 0.0,
        streakDays: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.todaySeconds = todaySeconds
        self.todayHours = todayHours
        self.todayMinutes = todayMinutes
        self.todayFormatted = todayFormatted
        self.goalMinutes = goalMinutes
        self.goalProgressFraction = min(max(goalProgressFraction, 0.0), 1.0)
        self.goalPercentageText = goalPercentageText
        self.isGoalAccomplished = isGoalAccomplished
        self.remainingMinutes = remainingMinutes
        self.currentMonthName = currentMonthName
        self.currentMonthHours = currentMonthHours
        self.previousMonthName = previousMonthName
        self.previousMonthHours = previousMonthHours
        self.monthDeltaHours = monthDeltaHours
        self.monthPercentageChange = monthPercentageChange
        self.totalSummaryFormatted = totalSummaryFormatted
        self.totalHours = totalHours
        self.streakDays = streakDays
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Root Data Snapshot

public struct WidgetDataSnapshot: Codable, Sendable, Equatable {
    public let nowPlaying: WidgetPlaybackSnapshot?
    public let recentBooks: [WidgetRecentBook]
    public let stats: WidgetStatsSnapshot
    public let lastUpdated: Date
    
    public init(
        nowPlaying: WidgetPlaybackSnapshot? = nil,
        recentBooks: [WidgetRecentBook] = [],
        stats: WidgetStatsSnapshot = WidgetStatsSnapshot(),
        lastUpdated: Date = Date()
    ) {
        self.nowPlaying = nowPlaying
        self.recentBooks = recentBooks
        self.stats = stats
        self.lastUpdated = lastUpdated
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nowPlaying = try container.decodeIfPresent(WidgetPlaybackSnapshot.self, forKey: .nowPlaying)
        self.recentBooks = (try? container.decode([WidgetRecentBook].self, forKey: .recentBooks)) ?? []
        self.stats = (try? container.decode(WidgetStatsSnapshot.self, forKey: .stats)) ?? WidgetStatsSnapshot()
        self.lastUpdated = (try? container.decode(Date.self, forKey: .lastUpdated)) ?? Date()
    }
}

// MARK: - Preview Mock Data

extension WidgetDataSnapshot {
    public static var preview: WidgetDataSnapshot {
        WidgetDataSnapshot(
            nowPlaying: WidgetPlaybackSnapshot.preview,
            recentBooks: WidgetRecentBook.previewList,
            stats: WidgetStatsSnapshot.preview,
            lastUpdated: Date()
        )
    }
}

extension WidgetPlaybackSnapshot {
    public static var preview: WidgetPlaybackSnapshot {
        WidgetPlaybackSnapshot(
            bookID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Project Hail Mary",
            author: "Andy Weir",
            currentTime: 14250,
            totalDuration: 57900,
            progress: 0.246,
            isPlaying: true,
            artworkData: nil,
            lastUpdated: Date()
        )
    }
}

extension WidgetRecentBook {
    public static var previewList: [WidgetRecentBook] {
        [
            WidgetRecentBook(
                id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                title: "Dune",
                author: "Frank Herbert",
                progress: 0.72,
                totalDuration: 75600,
                artworkData: nil,
                lastUpdated: Date().addingTimeInterval(-3600 * 2)
            ),
            WidgetRecentBook(
                id: UUID(uuidString: "33333333-4444-5555-6666-777777777777")!,
                title: "Atomic Habits",
                author: "James Clear",
                progress: 0.45,
                totalDuration: 20400,
                artworkData: nil,
                lastUpdated: Date().addingTimeInterval(-86400)
            ),
            WidgetRecentBook(
                id: UUID(uuidString: "44444444-5555-6666-7777-888888888888")!,
                title: "Pimsleur Spanish I",
                author: "Pimsleur Language",
                progress: 0.90,
                totalDuration: 54000,
                artworkData: nil,
                lastUpdated: Date().addingTimeInterval(-86400 * 3)
            )
        ]
    }
}

extension WidgetStatsSnapshot {
    public static var preview: WidgetStatsSnapshot {
        WidgetStatsSnapshot(
            todaySeconds: 2700,
            todayHours: 0,
            todayMinutes: 45,
            todayFormatted: "45m",
            goalMinutes: 60,
            goalProgressFraction: 0.75,
            goalPercentageText: "75%",
            isGoalAccomplished: false,
            remainingMinutes: 15,
            currentMonthName: "Sep",
            currentMonthHours: 18.5,
            previousMonthName: "Aug",
            previousMonthHours: 14.0,
            monthDeltaHours: 4.5,
            monthPercentageChange: 32.1,
            totalSummaryFormatted: "3d 8h 40m",
            totalHours: 80.6,
            streakDays: 5,
            lastUpdated: Date()
        )
    }
}
