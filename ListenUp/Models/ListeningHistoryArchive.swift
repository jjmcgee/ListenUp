import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Format & Document Types

/// Supported export formats for listening history backup archives.
public enum BackupArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON Archive"
    case zip = "Compressed ZIP Archive"
    
    public var id: String { rawValue }
    
    public var fileExtension: String {
        switch self {
        case .json: return "json"
        case .zip: return "zip"
        }
    }
    
    public var utType: UTType {
        switch self {
        case .json: return .json
        case .zip: return .zip
        }
    }
    
    public var formatDescription: String {
        switch self {
        case .json:
            return "Universal structured JSON archive. Ideal for backup, inspection, and restoring history."
        case .zip:
            return "Compressed package containing complete JSON data plus a human-readable text summary report."
        }
    }
}

/// SwiftUI `FileDocument` enabling native saving to Cloud directories (iCloud Drive, Google Drive)
/// or local directories on device via `.fileExporter`.
public struct ListeningHistoryArchiveDocument: FileDocument, Sendable {
    public static var readableContentTypes: [UTType] { [.json, .zip] }
    public static var writableContentTypes: [UTType] { [.json, .zip] }
    
    public var data: Data
    public var contentType: UTType
    
    public init(data: Data, contentType: UTType = .json) {
        self.data = data
        self.contentType = contentType
    }
    
    public init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = fileData
        self.contentType = configuration.contentType
    }
    
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Core Archive Models

/// Complete backup archive containing all listening history, daily streak logs,
/// audiobook progress, and aggregate metrics.
public struct ListeningHistoryArchive: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let appName = "ListenUp"
    
    // Header
    public let appName: String
    public let appVersion: String
    public let schemaVersion: Int
    public let exportDate: Date
    
    // Aggregated Metrics
    public let summary: ListeningHistorySummary
    
    // Daily Listening Activity Map & List
    public let dailyRecords: [String: Double]
    public let dailyActivity: [DailyActivityRecord]
    
    // Audiobook & Track History Records
    public let bookHistory: [BookHistoryRecord]
    
    public init(
        appName: String = ListeningHistoryArchive.appName,
        appVersion: String = "1.0",
        schemaVersion: Int = ListeningHistoryArchive.currentSchemaVersion,
        exportDate: Date = Date(),
        summary: ListeningHistorySummary,
        dailyRecords: [String: Double],
        dailyActivity: [DailyActivityRecord],
        bookHistory: [BookHistoryRecord]
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.exportDate = exportDate
        self.summary = summary
        self.dailyRecords = dailyRecords
        self.dailyActivity = dailyActivity
        self.bookHistory = bookHistory
    }
}

/// High-level listening statistics snapshot included in the archive.
public struct ListeningHistorySummary: Codable, Sendable {
    public let totalListeningSeconds: Double
    public let totalHours: Double
    public let totalSummaryFormatted: String
    public let months: Int
    public let days: Int
    public let hours: Int
    public let minutes: Int
    
    public let todayListeningSeconds: Double
    public let todayHours: Int
    public let todayMinutes: Int
    public let dailyGoalMinutes: Int
    
    public let completedTitlesCount: Int
    public let inProgressTitlesCount: Int
    public let totalHistoryTitlesCount: Int
    public let recordedDaysCount: Int
    
    public init(
        totalListeningSeconds: Double,
        totalHours: Double,
        totalSummaryFormatted: String,
        months: Int,
        days: Int,
        hours: Int,
        minutes: Int,
        todayListeningSeconds: Double,
        todayHours: Int,
        todayMinutes: Int,
        dailyGoalMinutes: Int,
        completedTitlesCount: Int,
        inProgressTitlesCount: Int,
        totalHistoryTitlesCount: Int,
        recordedDaysCount: Int
    ) {
        self.totalListeningSeconds = totalListeningSeconds
        self.totalHours = totalHours
        self.totalSummaryFormatted = totalSummaryFormatted
        self.months = months
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.todayListeningSeconds = todayListeningSeconds
        self.todayHours = todayHours
        self.todayMinutes = todayMinutes
        self.dailyGoalMinutes = dailyGoalMinutes
        self.completedTitlesCount = completedTitlesCount
        self.inProgressTitlesCount = inProgressTitlesCount
        self.totalHistoryTitlesCount = totalHistoryTitlesCount
        self.recordedDaysCount = recordedDaysCount
    }
}

/// Individual daily listening log entry.
public struct DailyActivityRecord: Codable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String // "YYYY-MM-DD"
    public let seconds: Double
    public let hours: Double
    public let formattedDuration: String
    
    public init(date: String, seconds: Double, hours: Double, formattedDuration: String) {
        self.date = date
        self.seconds = seconds
        self.hours = hours
        self.formattedDuration = formattedDuration
    }
}

/// Detailed listening progress and metadata record for an individual audiobook or collection.
public struct BookHistoryRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let author: String?
    public let kindRaw: String
    public let relativePath: String?
    public let totalDuration: Double
    public let formattedTotalDuration: String
    public let currentPosition: Double
    public let formattedCurrentPosition: String
    public let progress: Double
    public let progressPercentage: Int
    public let isCompleted: Bool
    public let completedDate: Date?
    public let formattedCompletedDate: String?
    public let isFileOffloaded: Bool
    public let isDeletedFromLibrary: Bool
    public let lastUpdated: Date
    public let childTracksCount: Int
    public let childTracks: [ChildTrackHistoryRecord]?
    
    public init(
        id: UUID,
        title: String,
        author: String? = nil,
        kindRaw: String,
        relativePath: String? = nil,
        totalDuration: Double,
        formattedTotalDuration: String,
        currentPosition: Double,
        formattedCurrentPosition: String,
        progress: Double,
        progressPercentage: Int,
        isCompleted: Bool,
        completedDate: Date? = nil,
        formattedCompletedDate: String? = nil,
        isFileOffloaded: Bool,
        isDeletedFromLibrary: Bool,
        lastUpdated: Date,
        childTracksCount: Int,
        childTracks: [ChildTrackHistoryRecord]? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kindRaw = kindRaw
        self.relativePath = relativePath
        self.totalDuration = totalDuration
        self.formattedTotalDuration = formattedTotalDuration
        self.currentPosition = currentPosition
        self.formattedCurrentPosition = formattedCurrentPosition
        self.progress = progress
        self.progressPercentage = progressPercentage
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.formattedCompletedDate = formattedCompletedDate
        self.isFileOffloaded = isFileOffloaded
        self.isDeletedFromLibrary = isDeletedFromLibrary
        self.lastUpdated = lastUpdated
        self.childTracksCount = childTracksCount
        self.childTracks = childTracks
    }
}

/// Lightweight child track record for multi-part audiobooks.
public struct ChildTrackHistoryRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let relativePath: String?
    public let totalDuration: Double
    public let sortOrder: Int
    
    public init(
        id: UUID,
        title: String,
        relativePath: String? = nil,
        totalDuration: Double,
        sortOrder: Int
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.totalDuration = totalDuration
        self.sortOrder = sortOrder
    }
}

// MARK: - Restore Result

/// Summary returned upon restoring a listening history archive.
public struct RestoreResult: Sendable, Equatable {
    public let restoredDaysCount: Int
    public let updatedBooksCount: Int
    public let newBooksCount: Int
    public let totalBooksCount: Int
    public let totalListeningSeconds: Double
    
    public init(
        restoredDaysCount: Int,
        updatedBooksCount: Int,
        newBooksCount: Int,
        totalBooksCount: Int,
        totalListeningSeconds: Double
    ) {
        self.restoredDaysCount = restoredDaysCount
        self.updatedBooksCount = updatedBooksCount
        self.newBooksCount = newBooksCount
        self.totalBooksCount = totalBooksCount
        self.totalListeningSeconds = totalListeningSeconds
    }
    
    public var summaryMessage: String {
        var parts: [String] = []
        if restoredDaysCount > 0 {
            parts.append("\(restoredDaysCount) daily activity \(restoredDaysCount == 1 ? "log" : "logs")")
        }
        if totalBooksCount > 0 {
            parts.append("\(totalBooksCount) audiobook \(totalBooksCount == 1 ? "record" : "records")")
        }
        if parts.isEmpty {
            return "Listening history backup restored successfully."
        }
        return "Restored " + parts.joined(separator: " and ") + "."
    }
}
