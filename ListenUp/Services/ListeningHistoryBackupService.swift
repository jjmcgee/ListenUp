import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import Compression

/// Service responsible for generating, exporting, compressing, and restoring
/// complete listening history backup archives for ListenUp.
public enum ListeningHistoryBackupService {
    
    // MARK: - Archive Construction
    
    /// Builds a comprehensive `ListeningHistoryArchive` containing all lifetime listening metrics,
    /// daily listening logs, streaks, and audiobook progress.
    @MainActor
    public static func buildArchive(
        items: [LibraryItem],
        dailyGoalMinutes: Int = 30
    ) -> ListeningHistoryArchive {
        let statsStore = ListeningStatsStore.shared
        
        let total = statsStore.totalBreakdown(from: items)
        let (todayH, todayM) = statsStore.todayHoursAndMinutes(from: items)
        let todaySecs = statsStore.todayListeningSeconds(from: items)
        let rawDailyRecords = statsStore.allDailyRecords
        
        // Convert daily records to sorted chronological entries (newest first)
        let dailyActivity: [DailyActivityRecord] = rawDailyRecords
            .map { key, seconds in
                DailyActivityRecord(
                    date: key,
                    seconds: seconds,
                    hours: seconds / 3600.0,
                    formattedDuration: TimeFormatting.formatVerbalDuration(seconds)
                )
            }
            .sorted { $0.date > $1.date }
        
        // Collect history audiobooks (items listened to or finished, excluding child tracks of multi-part items)
        let relevantItems = items.filter { item in
            item.kind != .folder && item.parent?.kind != .multiPart && (item.isCompleted || item.currentPosition > 0 || item.completedDate != nil)
        }
        .sorted {
            let d0 = $0.completedDate ?? $0.lastUpdated
            let d1 = $1.completedDate ?? $1.lastUpdated
            return d0 > d1
        }
        
        let completedCount = items.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && $0.isCompleted }.count
        let inProgressCount = items.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && !$0.isCompleted && $0.currentPosition > 0 && !$0.isDeletedFromLibrary }.count
        
        let bookRecords: [BookHistoryRecord] = relevantItems.map { item in
            let childTracks: [ChildTrackHistoryRecord]? = item.kind == .multiPart ? item.sortedChildren.map { child in
                ChildTrackHistoryRecord(
                    id: child.id,
                    title: child.title,
                    relativePath: child.relativePath,
                    totalDuration: child.totalDuration,
                    sortOrder: child.sortOrder
                )
            } : nil
            
            return BookHistoryRecord(
                id: item.id,
                title: item.title,
                author: item.author,
                kindRaw: item.kindRaw,
                relativePath: item.relativePath,
                totalDuration: item.totalDuration,
                formattedTotalDuration: item.formattedTotalDuration,
                currentPosition: item.currentPosition,
                formattedCurrentPosition: TimeFormatting.formatTimestamp(item.currentPosition),
                progress: item.progress,
                progressPercentage: Int(item.progress * 100),
                isCompleted: item.isCompleted,
                completedDate: item.completedDate,
                formattedCompletedDate: item.formattedCompletedDate,
                isFileOffloaded: item.isFileOffloaded,
                isDeletedFromLibrary: item.isDeletedFromLibrary,
                lastUpdated: item.lastUpdated,
                childTracksCount: item.children?.count ?? 0,
                childTracks: childTracks
            )
        }
        
        let summary = ListeningHistorySummary(
            totalListeningSeconds: total.totalSeconds,
            totalHours: total.totalHours,
            totalSummaryFormatted: total.formattedSummary,
            months: total.months,
            days: total.days,
            hours: total.hours,
            minutes: total.minutes,
            todayListeningSeconds: todaySecs,
            todayHours: todayH,
            todayMinutes: todayM,
            dailyGoalMinutes: dailyGoalMinutes,
            completedTitlesCount: completedCount,
            inProgressTitlesCount: inProgressCount,
            totalHistoryTitlesCount: bookRecords.count,
            recordedDaysCount: rawDailyRecords.count
        )
        
        return ListeningHistoryArchive(
            appName: ListeningHistoryArchive.appName,
            appVersion: "1.0",
            schemaVersion: ListeningHistoryArchive.currentSchemaVersion,
            exportDate: Date(),
            summary: summary,
            dailyRecords: rawDailyRecords,
            dailyActivity: dailyActivity,
            bookHistory: bookRecords
        )
    }
    
    // MARK: - Serialization
    
    /// Encodes a `ListeningHistoryArchive` into formatted, indented UTF-8 JSON data.
    public static func encodeJSON(archive: ListeningHistoryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }
    
    /// Decodes a `ListeningHistoryArchive` from JSON or decompressed archive data.
    public static func decodeJSON(from data: Data) throws -> ListeningHistoryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ListeningHistoryArchive.self, from: data)
    }
    
    // MARK: - Human-Readable Summary Report
    
    /// Generates a human-readable text document summarizing the user's listening history.
    public static func generateSummaryReport(for archive: ListeningHistoryArchive) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: archive.exportDate)
        
        var report = """
        ================================================================================
                            LISTENUP LISTENING HISTORY BACKUP REPORT
        ================================================================================
        Exported: \(dateString)
        Application: \(archive.appName) v\(archive.appVersion) (Schema v\(archive.schemaVersion))
        
        LIFETIME LISTENING SUMMARY
        --------------------------------------------------------------------------------
        • Total Listening Time: \(archive.summary.totalSummaryFormatted) (\(String(format: "%.1f", archive.summary.totalHours)) hours)
        • Audiobooks Completed: \(archive.summary.completedTitlesCount)
        • Audiobooks In Progress: \(archive.summary.inProgressTitlesCount)
        • Total Titles in History: \(archive.summary.totalHistoryTitlesCount)
        • Recorded Listening Days: \(archive.summary.recordedDaysCount) days
        • Daily Target Goal: \(archive.summary.dailyGoalMinutes) minutes
        
        DAILY LISTENING ACTIVITY LOGS
        --------------------------------------------------------------------------------
        """
        
        if archive.dailyActivity.isEmpty {
            report += "\n(No daily listening logs recorded)\n"
        } else {
            for day in archive.dailyActivity.prefix(30) {
                report += "\n• \(day.date): \(day.formattedDuration) (\(String(format: "%.1fh", day.hours)))"
            }
            if archive.dailyActivity.count > 30 {
                report += "\n... and \(archive.dailyActivity.count - 30) older daily records preserved in archive."
            }
            report += "\n"
        }
        
        report += """
        
        AUDIOBOOK & TRACK PROGRESS
        --------------------------------------------------------------------------------
        """
        
        if archive.bookHistory.isEmpty {
            report += "\n(No audiobooks in history)\n"
        } else {
            for (index, book) in archive.bookHistory.enumerated() {
                let authorStr = book.author.map { " by \($0)" } ?? ""
                let statusStr = book.isCompleted ? "Completed (\(book.formattedCompletedDate ?? "Yes"))" : "\(book.progressPercentage)% listened"
                report += """
                
                \(index + 1). \(book.title)\(authorStr)
                   - Status: \(statusStr)
                   - Progress: \(book.formattedCurrentPosition) / \(book.formattedTotalDuration)
                   - Offloaded: \(book.isFileOffloaded ? "Yes" : "No") | Archived: \(book.isDeletedFromLibrary ? "Yes" : "No")
                """
            }
            report += "\n"
        }
        
        report += """
        ================================================================================
        """
        return report
    }
    
    // MARK: - Zip Compression & Packaging
    
    /// Compresses `listening_history.json` and a human-readable `listening_summary.txt` report
    /// into a valid ZIP archive without external dependencies.
    public static func createZipArchive(for archive: ListeningHistoryArchive) throws -> Data {
        let jsonData = try encodeJSON(archive: archive)
        let summaryText = generateSummaryReport(for: archive)
        let summaryData = summaryText.data(using: .utf8) ?? Data()
        
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ListenUp_Backup_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }
        
        let jsonFileURL = tempDirectory.appendingPathComponent("listening_history.json")
        let summaryFileURL = tempDirectory.appendingPathComponent("listening_summary.txt")
        
        try jsonData.write(to: jsonFileURL)
        try summaryData.write(to: summaryFileURL)
        
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        var zipData: Data?
        var innerError: Error?
        
        coordinator.coordinate(readingItemAt: tempDirectory, options: [.forUploading], error: &coordinationError) { zipURL in
            do {
                zipData = try Data(contentsOf: zipURL)
            } catch {
                innerError = error
            }
        }
        
        if let error = coordinationError { throw error }
        if let error = innerError { throw error }
        guard let finalZip = zipData else { throw CocoaError(.fileWriteUnknown) }
        
        return finalZip
    }
    
    // MARK: - Export Payload Preparation
    
    /// Prepares the export data, content type, and default filename from an existing archive.
    public static func createExportPayload(
        format: BackupArchiveFormat,
        archive: ListeningHistoryArchive
    ) throws -> (data: Data, contentType: UTType, filename: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = dateFormatter.string(from: archive.exportDate)
        
        switch format {
        case .json:
            let jsonData = try encodeJSON(archive: archive)
            let filename = "ListenUp-ListeningHistory-\(dateString).json"
            return (jsonData, .json, filename)
            
        case .zip:
            let zipData = try createZipArchive(for: archive)
            let filename = "ListenUp-ListeningHistory-\(dateString).zip"
            return (zipData, .zip, filename)
        }
    }
    
    /// Prepares the export data, content type, and default filename for saving to Cloud/Files.
    @MainActor
    public static func createExportPayload(
        format: BackupArchiveFormat,
        items: [LibraryItem],
        dailyGoalMinutes: Int = 30
    ) throws -> (data: Data, contentType: UTType, filename: String) {
        let archive = buildArchive(items: items, dailyGoalMinutes: dailyGoalMinutes)
        return try createExportPayload(format: format, archive: archive)
    }
    
    // MARK: - Zip Extraction
    
    /// Extracts files from a ZIP archive by parsing the ZIP Central Directory.
    public static func extractFilesFromZip(zipData: Data) -> [String: Data] {
        var result: [String: Data] = [:]
        var offset = 0
        let count = zipData.count
        
        while offset + 46 <= count {
            // Check for Central Directory entry signature: 0x02014b50 (PK\x01\x02)
            if zipData[offset] == 0x50 && zipData[offset+1] == 0x4b && zipData[offset+2] == 0x01 && zipData[offset+3] == 0x02 {
                let method = zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 10, as: UInt16.self) }
                let compSize = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self) })
                let uncompSize = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self) })
                let nameLen = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 28, as: UInt16.self) })
                let extraLen = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 30, as: UInt16.self) })
                let commentLen = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 32, as: UInt16.self) })
                let localHeaderOffset = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 42, as: UInt32.self) })
                
                let nameStart = offset + 46
                let nameEnd = nameStart + nameLen
                let name: String
                if nameEnd <= count, let str = String(data: zipData.subdata(in: nameStart..<nameEnd), encoding: .utf8) {
                    name = str
                } else {
                    name = ""
                }
                
                // Read local header to locate payload start
                if localHeaderOffset + 30 <= count {
                    let localNameLen = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: localHeaderOffset + 26, as: UInt16.self) })
                    let localExtraLen = Int(zipData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: localHeaderOffset + 28, as: UInt16.self) })
                    let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
                    let dataEnd = dataStart + compSize
                    
                    if dataEnd <= count {
                        let rawData = zipData.subdata(in: dataStart..<dataEnd)
                        if method == 0 {
                            result[name] = rawData
                        } else if method == 8 && uncompSize > 0 {
                            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompSize)
                            defer { destBuffer.deallocate() }
                            
                            let decodedSize = rawData.withUnsafeBytes { rawBuffer -> Int in
                                guard let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                                return compression_decode_buffer(destBuffer, uncompSize, ptr, rawData.count, nil, COMPRESSION_ZLIB)
                            }
                            if decodedSize > 0 {
                                result[name] = Data(bytes: destBuffer, count: decodedSize)
                            }
                        }
                    }
                }
                
                offset = nameStart + nameLen + extraLen + commentLen
            } else {
                offset += 1
            }
        }
        
        return result
    }
    
    // MARK: - Archive Parsing (Auto-detecting JSON or ZIP)
    
    /// Parses an archive from raw file Data, automatically detecting whether it is a `.json` file or `.zip` package.
    public static func parseArchive(from data: Data) throws -> ListeningHistoryArchive {
        // Check for ZIP magic signature: PK\x03\x04
        if data.count >= 4 && data[0] == 0x50 && data[1] == 0x4b && data[2] == 0x03 && data[3] == 0x04 {
            let extracted = extractFilesFromZip(zipData: data)
            // Look for JSON file
            for (filename, fileData) in extracted {
                if filename.hasSuffix(".json") {
                    if let archive = try? decodeJSON(from: fileData) {
                        return archive
                    }
                }
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        
        // Otherwise parse directly as JSON
        return try decodeJSON(from: data)
    }
    
    // MARK: - History Restoration
    
    /// Restores listening history from an archive into SwiftData and the `ListeningStatsStore`.
    @MainActor
    public static func restore(
        from archive: ListeningHistoryArchive,
        into modelContext: ModelContext
    ) -> RestoreResult {
        let statsStore = ListeningStatsStore.shared
        
        // 1. Restore daily listening logs
        statsStore.restoreDailyRecords(archive.dailyRecords, merge: true)
        
        // 2. Fetch all existing LibraryItems to resolve conflict and merge progress
        let descriptor = FetchDescriptor<LibraryItem>()
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []
        
        var existingById: [UUID: LibraryItem] = [:]
        for item in existingItems {
            existingById[item.id] = item
        }
        
        var updatedCount = 0
        var newCount = 0
        
        for record in archive.bookHistory {
            if let existing = existingById[record.id] {
                // Merge: Take furthest progress and newest completion
                let isRecordNewer = record.lastUpdated >= existing.lastUpdated
                let isRecordFurther = record.currentPosition > existing.currentPosition
                
                if isRecordNewer || isRecordFurther {
                    existing.currentPosition = max(existing.currentPosition, record.currentPosition)
                    existing.isCompleted = existing.isCompleted || record.isCompleted
                    if record.isCompleted && existing.completedDate == nil {
                        existing.completedDate = record.completedDate ?? Date()
                    }
                    existing.lastUpdated = max(existing.lastUpdated, record.lastUpdated)
                    updatedCount += 1
                }
            } else {
                // Book not found in current library: create as offloaded archived history item
                let kind = ItemKind(rawValue: record.kindRaw) ?? .singleFile
                let restoredItem = LibraryItem(
                    id: record.id,
                    title: record.title,
                    author: record.author,
                    kind: kind,
                    relativePath: record.relativePath,
                    totalDuration: record.totalDuration,
                    currentPosition: record.currentPosition,
                    isCompleted: record.isCompleted,
                    completedDate: record.completedDate,
                    isFileOffloaded: true,
                    isDeletedFromLibrary: record.isDeletedFromLibrary,
                    lastUpdated: record.lastUpdated
                )
                
                modelContext.insert(restoredItem)
                existingById[restoredItem.id] = restoredItem
                newCount += 1
            }
        }
        
        try? modelContext.save()
        statsStore.handleDayChanged()
        statsStore.syncToWidgets()
        
        return RestoreResult(
            restoredDaysCount: archive.dailyRecords.count,
            updatedBooksCount: updatedCount,
            newBooksCount: newCount,
            totalBooksCount: updatedCount + newCount,
            totalListeningSeconds: archive.summary.totalListeningSeconds
        )
    }
}

// MARK: - Lazy Transferable Archive Export Types

/// Transferable representation for exporting JSON listening history backups lazily via ShareLink.
public struct JsonBackupArchiveTransferable: Transferable, Sendable {
    public let archive: ListeningHistoryArchive
    
    public init(archive: ListeningHistoryArchive) {
        self.archive = archive
    }
    
    public var filename: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return "ListenUp-ListeningHistory-\(dateFormatter.string(from: archive.exportDate)).json"
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in
            try ListeningHistoryBackupService.encodeJSON(archive: item.archive)
        }
        .suggestedFileName { $0.filename }
    }
}

/// Transferable representation for exporting ZIP listening history backups lazily via ShareLink.
public struct ZipBackupArchiveTransferable: Transferable, Sendable {
    public let archive: ListeningHistoryArchive
    
    public init(archive: ListeningHistoryArchive) {
        self.archive = archive
    }
    
    public var filename: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return "ListenUp-ListeningHistory-\(dateFormatter.string(from: archive.exportDate)).zip"
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .zip) { item in
            try ListeningHistoryBackupService.createZipArchive(for: item.archive)
        }
        .suggestedFileName { $0.filename }
    }
}
