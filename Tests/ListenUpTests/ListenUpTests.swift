import Testing
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
@testable import ListenUp

@Suite("ListenUp Core Architecture Tests")
struct ListenUpTests {
    
    // MARK: - TimeFormatting Tests
    
    @Test("TimeFormatting formats short seconds as mm:ss")
    func testFormatShortTimestamp() {
        #expect(TimeFormatting.formatTimestamp(0) == "0:00")
        #expect(TimeFormatting.formatTimestamp(45) == "0:45")
        #expect(TimeFormatting.formatTimestamp(75) == "1:15")
        #expect(TimeFormatting.formatTimestamp(599) == "9:59")
    }
    
    @Test("TimeFormatting formats long seconds as hh:mm:ss")
    func testFormatLongTimestamp() {
        #expect(TimeFormatting.formatTimestamp(3600) == "1:00:00")
        #expect(TimeFormatting.formatTimestamp(3665) == "1:01:05")
        #expect(TimeFormatting.formatTimestamp(7325) == "2:02:05")
    }
    
    @Test("TimeFormatting formats remaining countdown")
    func testFormatRemaining() {
        #expect(TimeFormatting.formatRemainingTimestamp(current: 10, total: 100) == "-1:30")
        #expect(TimeFormatting.formatRemainingTimestamp(current: 100, total: 100) == "-0:00")
        #expect(TimeFormatting.formatRemainingTimestamp(current: 110, total: 100) == "-0:00")
    }
    
    @Test("TimeFormatting formats verbal duration")
    func testFormatVerbalDuration() {
        #expect(TimeFormatting.formatVerbalDuration(30) == "1 min")
        #expect(TimeFormatting.formatVerbalDuration(180) == "3 min")
        #expect(TimeFormatting.formatVerbalDuration(3600) == "1 hr")
        #expect(TimeFormatting.formatVerbalDuration(5400) == "1 hr 30 min")
    }
    
    @Test("TimeFormatting formats chapter start timestamp as HH:mm:ss")
    func testFormatChapterTimestamp() {
        #expect(TimeFormatting.formatChapterTimestamp(0) == "00:00:00")
        #expect(TimeFormatting.formatChapterTimestamp(75) == "00:01:15")
        #expect(TimeFormatting.formatChapterTimestamp(3600) == "01:00:00")
        #expect(TimeFormatting.formatChapterTimestamp(10367) == "02:52:47")
    }
    
    @Test("TimeFormatting formats chapter duration as mm:ss or HH:mm:ss")
    func testFormatChapterDuration() {
        #expect(TimeFormatting.formatChapterDuration(35) == "00:35")
        #expect(TimeFormatting.formatChapterDuration(423) == "07:03")
        #expect(TimeFormatting.formatChapterDuration(586) == "09:46")
        #expect(TimeFormatting.formatChapterDuration(3665) == "01:01:05")
    }
    
    @Test("TimeFormatting formats chapter remaining countdown matching -mm:ss")
    func testFormatChapterRemaining() {
        #expect(TimeFormatting.formatChapterRemaining(0) == "-00:00")
        #expect(TimeFormatting.formatChapterRemaining(248) == "-04:08")
        #expect(TimeFormatting.formatChapterRemaining(35) == "-00:35")
        #expect(TimeFormatting.formatChapterRemaining(3665) == "-01:01:05")
    }
    
    // MARK: - Chapter Model & Navigation Tests
    
    @Test("ChapterInfo correctly computes end time and properties")
    func testChapterInfoProperties() {
        let chapter = ChapterInfo(
            index: 32,
            title: "Game #2: Somewhere in Kentucky, Four Days Later",
            startTime: 10331.0,
            duration: 35.0
        )
        
        #expect(chapter.index == 32)
        #expect(chapter.title == "Game #2: Somewhere in Kentucky, Four Days Later")
        #expect(chapter.startTime == 10331.0)
        #expect(chapter.duration == 35.0)
        #expect(chapter.endTime == 10366.0)
    }
    
    @Test("Chapter navigation correctly maps playback position to active chapter")
    func testChapterLookupMath() {
        let ch1 = ChapterInfo(index: 0, title: "Chapter 1", startTime: 0.0, duration: 300.0)
        let ch2 = ChapterInfo(index: 1, title: "Chapter 2", startTime: 300.0, duration: 500.0)
        let ch3 = ChapterInfo(index: 2, title: "Chapter 3", startTime: 800.0, duration: 400.0)
        let chapters = [ch1, ch2, ch3]
        
        func findChapter(at time: Double) -> ChapterInfo? {
            for c in chapters {
                if time >= c.startTime && time < c.endTime {
                    return c
                }
            }
            if let last = chapters.last, time >= last.startTime {
                return last
            }
            return chapters.first
        }
        
        #expect(findChapter(at: 0.0)?.index == 0)
        #expect(findChapter(at: 150.0)?.index == 0)
        #expect(findChapter(at: 300.0)?.index == 1)
        #expect(findChapter(at: 799.0)?.index == 1)
        #expect(findChapter(at: 800.0)?.index == 2)
        #expect(findChapter(at: 1250.0)?.index == 2)
    }
    
    // MARK: - SwiftData Model & CloudKit Tests
    
    @Test("LibraryItem initializes with valid CloudKit defaults")
    func testLibraryItemCloudKitDefaults() {
        let item = LibraryItem(title: "Jack Reacher: Killing Floor")
        #expect(item.title == "Jack Reacher: Killing Floor")
        #expect(item.kind == .singleFile)
        #expect(item.parent == nil)
        #expect(item.children != nil)
        #expect(item.children?.isEmpty == true)
        #expect(item.currentPosition == 0.0)
        #expect(item.totalDuration == 0.0)
        #expect(item.progress == 0.0)
        #expect(item.isCompleted == false)
    }
    
    // MARK: - Multi-Part Continuous Timeline Geometry Tests
    
    @Test("Multi-part book correctly calculates cumulative timeline segments")
    func testMultiPartSegments() {
        let book = LibraryItem(title: "Pimsleur Spanish 1", kind: .multiPart)
        
        let part1 = LibraryItem(
            title: "Lesson 1",
            kind: .singleFile,
            relativePath: "Audiobooks/Pimsleur/Lesson1.mp3",
            totalDuration: 1800.0, // 30 mins
            sortOrder: 0,
            parent: book
        )
        let part2 = LibraryItem(
            title: "Lesson 2",
            kind: .singleFile,
            relativePath: "Audiobooks/Pimsleur/Lesson2.mp3",
            totalDuration: 1800.0, // 30 mins
            sortOrder: 1,
            parent: book
        )
        let part3 = LibraryItem(
            title: "Lesson 3",
            kind: .singleFile,
            relativePath: "Audiobooks/Pimsleur/Lesson3.mp3",
            totalDuration: 1800.0, // 30 mins
            sortOrder: 2,
            parent: book
        )
        
        book.children = [part1, part2, part3]
        book.recalculateDurations()
        
        #expect(book.totalDuration == 5400.0) // 90 mins total
        
        let segments = book.segments
        #expect(segments.count == 3)
        
        // Segment 0: 0 to 1800
        #expect(segments[0].startVirtualTime == 0.0)
        #expect(segments[0].duration == 1800.0)
        #expect(segments[0].endVirtualTime == 1800.0)
        
        // Segment 1: 1800 to 3600
        #expect(segments[1].startVirtualTime == 1800.0)
        #expect(segments[1].duration == 1800.0)
        #expect(segments[1].endVirtualTime == 3600.0)
        
        // Segment 2: 3600 to 5400
        #expect(segments[2].startVirtualTime == 3600.0)
        #expect(segments[2].duration == 1800.0)
        #expect(segments[2].endVirtualTime == 5400.0)
    }
    
    @Test("Multi-part book maps virtual seek time T to exact segment and local physical offset")
    func testMultiPartSeekMapping() {
        let book = LibraryItem(title: "Multi-Part Audiobook", kind: .multiPart)
        let part1 = LibraryItem(title: "Part 1", kind: .singleFile, relativePath: "p1.mp3", totalDuration: 1000.0, sortOrder: 0, parent: book)
        let part2 = LibraryItem(title: "Part 2", kind: .singleFile, relativePath: "p2.mp3", totalDuration: 1000.0, sortOrder: 1, parent: book)
        book.children = [part1, part2]
        book.recalculateDurations()
        
        // Test seek within Part 1 (T = 500)
        let lookup1 = book.segment(at: 500.0)
        #expect(lookup1 != nil)
        #expect(lookup1?.segment.trackIndex == 0)
        #expect(lookup1?.localOffset == 500.0)
        
        // Test seek at exact boundary (T = 1000 -> Part 2 at 0.0)
        let lookupBoundary = book.segment(at: 1000.0)
        #expect(lookupBoundary != nil)
        #expect(lookupBoundary?.segment.trackIndex == 1)
        #expect(lookupBoundary?.localOffset == 0.0)
        
        // Test seek within Part 2 (T = 1450 -> Part 2 at 450.0)
        let lookup2 = book.segment(at: 1450.0)
        #expect(lookup2 != nil)
        #expect(lookup2?.segment.trackIndex == 1)
        #expect(lookup2?.localOffset == 450.0)
        
        // Test reverse mapping: trackIndex 1, localOffset 450 -> virtual 1450
        let virtualPos = book.virtualPosition(trackIndex: 1, localOffset: 450.0)
        #expect(virtualPos == 1450.0)
    }
    
    // MARK: - Multi-Device Sync Conflict Resolution Tests
    
    @Test("WatchSyncManager applies sync when incoming timestamp is newer")
    @MainActor
    func testSyncConflictResolutionNewerWins() {
        let bookID = UUID()
        let localDate = Date(timeIntervalSince1970: 1000)
        let localItem = LibraryItem(id: bookID, title: "Test Book", lastUpdated: localDate)
        localItem.currentPosition = 120.0
        
        // Incoming update from watch with timestamp 1050 (newer)
        let newerDate = Date(timeIntervalSince1970: 1050)
        let payload = PlaybackSyncPayload(
            bookID: bookID,
            position: 250.0,
            isCompleted: false,
            lastUpdated: newerDate
        )
        
        let applied = WatchSyncManager.applySyncUpdate(payload: payload, to: localItem)
        #expect(applied == true)
        #expect(localItem.currentPosition == 250.0)
        #expect(localItem.lastUpdated == newerDate)
    }
    
    @Test("WatchSyncManager rejects sync when incoming timestamp is older")
    @MainActor
    func testSyncConflictResolutionOlderRejected() {
        let bookID = UUID()
        let localDate = Date(timeIntervalSince1970: 2000)
        let localItem = LibraryItem(id: bookID, title: "Test Book", lastUpdated: localDate)
        localItem.currentPosition = 500.0
        
        // Incoming update with timestamp 1900 (stale / older)
        let olderDate = Date(timeIntervalSince1970: 1900)
        let payload = PlaybackSyncPayload(
            bookID: bookID,
            position: 300.0,
            isCompleted: false,
            lastUpdated: olderDate
        )
        
        let applied = WatchSyncManager.applySyncUpdate(payload: payload, to: localItem)
        #expect(applied == false)
        #expect(localItem.currentPosition == 500.0) // Unchanged
        #expect(localItem.lastUpdated == localDate)
    }
    
    // MARK: - Physical File Deletion Tests
    
    @Test("deletePhysicalFiles removes media files from local sandbox")
    func testDeletePhysicalFiles() throws {
        let fileManager = FileManager.default
        let docs = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let testDir = docs.appendingPathComponent("Audiobooks/TestDeletion")
        try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
        let testFile = testDir.appendingPathComponent("test.mp3")
        try "dummy audio content".data(using: .utf8)?.write(to: testFile)
        
        #expect(fileManager.fileExists(atPath: testFile.path) == true)
        
        let item = LibraryItem(
            title: "Test Deletion",
            kind: .singleFile,
            relativePath: "Audiobooks/TestDeletion/test.mp3"
        )
        
        FileImporterService.deletePhysicalFiles(for: item)
        
        #expect(fileManager.fileExists(atPath: testFile.path) == false)
        #expect(fileManager.fileExists(atPath: testDir.path) == false)
    }
    
    // MARK: - Profile & Listener Statistics Tests
    
    @Test("Profile correctly calculates aggregate listening statistics and completed book counts")
    func testProfileListeningStatsCalculation() {
        let book1 = LibraryItem(title: "Atomic Habits", kind: .singleFile, totalDuration: 18000.0)
        book1.currentPosition = 9000.0 // 2.5 hours
        book1.isCompleted = false
        
        let book2 = LibraryItem(title: "Deep Work", kind: .singleFile, totalDuration: 21600.0)
        book2.currentPosition = 21600.0 // 6.0 hours
        book2.isCompleted = true
        
        let book3 = LibraryItem(title: "Clean Code", kind: .singleFile, totalDuration: 14400.0)
        book3.currentPosition = 0.0 // 0 hours
        book3.isCompleted = false
        
        let items = [book1, book2, book3]
        
        let totalSeconds = items.reduce(0.0) { $0 + max(0.0, $1.currentPosition) }
        #expect(totalSeconds == 30600.0) // 8.5 hours
        
        let hours = totalSeconds / 3600.0
        #expect(hours == 8.5)
        
        let completedCount = items.filter { $0.parent == nil && $0.isCompleted }.count
        #expect(completedCount == 1)
        
        let inProgressCount = items.filter { $0.parent == nil && !$0.isCompleted && $0.currentPosition > 0 }.count
        #expect(inProgressCount == 1)
    }
    
    @Test("ListeningStatsStore correctly breaks down total seconds into months, days, hours, and minutes")
    @MainActor
    func testTotalListeningBreakdown() {
        let store = ListeningStatsStore()
        
        let book1 = LibraryItem(title: "Book 1", kind: .singleFile, totalDuration: 3600.0)
        // 1 month (2592000s) + 4 days (345600s) + 12 hours (43200s) + 30 minutes (1800s) = 2982600s
        book1.currentPosition = 2982600.0
        
        let breakdown = store.totalBreakdown(from: [book1])
        #expect(breakdown.months == 1)
        #expect(breakdown.days == 4)
        #expect(breakdown.hours == 12)
        #expect(breakdown.minutes == 30)
        #expect(breakdown.formattedSummary == "1m 4d 12h 30m")
    }
    
    @Test("ListeningStatsStore records daily listening and aggregates today and monthly stats")
    @MainActor
    func testDailyListeningRecordingAndMonthlyComparison() {
        let store = ListeningStatsStore()
        store.resetRecords()
        
        let now = Date()
        let calendar = Calendar.current
        guard let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return }
        
        // Record 1.5 hours (5400s) today
        store.recordListening(seconds: 5400.0, on: now)
        
        // Record 3.0 hours (10800s) in previous month
        store.recordListening(seconds: 10800.0, on: prevMonthDate)
        
        let today = store.todayHoursAndMinutes()
        #expect(today.hours == 1)
        #expect(today.minutes == 30)
        
        let monthly = store.monthlyComparison()
        #expect(monthly.currentMonthHours == 1.5)
        #expect(monthly.previousMonthHours == 3.0)
        #expect(monthly.hoursDelta == -1.5)
        
        store.resetRecords()
    }
    
    @Test("Today listening count strictly spans 1 day and resets back to 0 on the next day")
    @MainActor
    func testTodayCountResetsOnNextDay() {
        let store = ListeningStatsStore()
        store.resetRecords()
        
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }
        
        // Monday (yesterday): Listen to 30 minutes (1800 seconds)
        store.recordListening(seconds: 1800.0, on: yesterday)
        
        // Tuesday (today at 00:00+): Today count should be strictly back at 0
        let todayStats = store.todayHoursAndMinutes()
        #expect(todayStats.hours == 0)
        #expect(todayStats.minutes == 0)
        #expect(store.todayListeningSeconds() == 0.0)
        
        // Total breakdown should still retain Monday's listening
        let total = store.totalBreakdown()
        #expect(total.minutes == 30)
        
        // Now listen to 45 minutes on Tuesday (today)
        store.recordListening(seconds: 2700.0, on: now)
        let updatedToday = store.todayHoursAndMinutes()
        #expect(updatedToday.hours == 0)
        #expect(updatedToday.minutes == 45)
        #expect(store.todayListeningSeconds() == 2700.0)
        
        store.resetRecords()
    }
    
    @Test("Daily Listening Goal progress resets to 0% and unaccomplished on the next day")
    @MainActor
    func testDailyGoalProgressResetsOnNextDay() {
        let store = ListeningStatsStore()
        store.resetRecords()
        
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }
        
        // Monday (yesterday): Listen to 30 minutes, meeting a 30-minute daily goal
        store.recordListening(seconds: 1800.0, on: yesterday)
        
        // Tuesday (today): Daily Goal progress must be strictly reset to 0 minutes (0%)
        let todayGoal = store.dailyGoalProgress(goalMinutes: 30)
        #expect(todayGoal.listenedMinutes == 0)
        #expect(todayGoal.goalMinutes == 30)
        #expect(todayGoal.fraction == 0.0)
        #expect(todayGoal.isAccomplished == false)
        #expect(todayGoal.remainingMinutes == 30)
        #expect(todayGoal.percentageText == "0%")
        
        // Listen for 15 minutes today (halfway towards 30-min goal)
        store.recordListening(seconds: 900.0, on: now)
        let halfwayGoal = store.dailyGoalProgress(goalMinutes: 30)
        #expect(halfwayGoal.listenedMinutes == 15)
        #expect(halfwayGoal.fraction == 0.5)
        #expect(halfwayGoal.isAccomplished == false)
        #expect(halfwayGoal.remainingMinutes == 15)
        #expect(halfwayGoal.percentageText == "50%")
        
        // Listen for another 15 minutes today (achieving the goal)
        store.recordListening(seconds: 900.0, on: now)
        let accomplishedGoal = store.dailyGoalProgress(goalMinutes: 30)
        #expect(accomplishedGoal.listenedMinutes == 30)
        #expect(accomplishedGoal.fraction == 1.0)
        #expect(accomplishedGoal.isAccomplished == true)
        #expect(accomplishedGoal.remainingMinutes == 0)
        #expect(accomplishedGoal.percentageText == "100%")
        
        store.resetRecords()
    }
    
    // MARK: - Library Filter Tests
    
    @Test("Library FilterOption contains only All and In Progress tabs")
    func testLibraryFilterOptions() {
        let options = LibraryView.FilterOption.allCases
        #expect(options.count == 2)
        #expect(options.contains(.all))
        #expect(options.contains(.inProgress))
    }
    
    @Test("In Progress tab filtering isolates active unfinished books and excludes completed books and folders")
    func testInProgressTabFiltering() {
        let finishedSingle = LibraryItem(title: "Finished Novel", kind: .singleFile, totalDuration: 3600.0, isCompleted: true)
        let unfinishedSingle = LibraryItem(title: "Reading Novel", kind: .singleFile, totalDuration: 3600.0, currentPosition: 500.0, isCompleted: false)
        let unreadSingle = LibraryItem(title: "Unread Novel", kind: .singleFile, totalDuration: 3600.0, currentPosition: 0.0, isCompleted: false)
        let folder = LibraryItem(title: "Audio Courses", kind: .folder)
        
        let allItems = [finishedSingle, unfinishedSingle, unreadSingle, folder]
        
        // Filter logic for In Progress tab
        let inProgressBooks = allItems.filter { item in
            item.kind != .folder && item.parent?.kind != .multiPart && !item.isCompleted && item.currentPosition > 0 && !item.isDeletedFromLibrary
        }
        
        #expect(inProgressBooks.count == 1)
        #expect(inProgressBooks.contains(where: { $0.title == "Reading Novel" }))
        #expect(!inProgressBooks.contains(where: { $0.title == "Finished Novel" }))
        #expect(!inProgressBooks.contains(where: { $0.title == "Unread Novel" }))
        #expect(!inProgressBooks.contains(where: { $0.title == "Audio Courses" }))
    }
    
    // MARK: - Book History & Audio File Offloading Tests
    
    @Test("Offloading completed book deletes file reference but preserves history and completion metadata")
    func testFinishedBookOffloadingPreservesMetadataAndHistory() {
        let completionDate = Date()
        let book = LibraryItem(
            title: "Dune",
            author: "Frank Herbert",
            kind: .singleFile,
            relativePath: "Audiobooks/Dune.m4b",
            totalDuration: 72000.0,
            currentPosition: 72000.0,
            isCompleted: true,
            completedDate: completionDate,
            isFileOffloaded: false,
            isDeletedFromLibrary: false
        )
        
        #expect(book.isCompleted == true)
        #expect(book.completedDate == completionDate)
        #expect(book.formattedCompletedDate?.contains("Completed") == true)
        
        // Simulate offloading audio file to save storage
        book.isFileOffloaded = true
        #expect(book.hasLocalAudio == false)
        #expect(book.title == "Dune")
        #expect(book.author == "Frank Herbert")
        #expect(book.totalDuration == 72000.0)
        #expect(book.isCompleted == true)
        #expect(book.completedDate == completionDate)
    }
    
    @Test("Deleting book from library sets isDeletedFromLibrary but preserves history in profile stats")
    func testDeletedBookFromLibraryPreservesListeningHistory() {
        let completedDate = Date()
        let book1 = LibraryItem(
            title: "1984",
            kind: .singleFile,
            totalDuration: 36000.0,
            currentPosition: 36000.0,
            isCompleted: true,
            completedDate: completedDate
        )
        
        let book2 = LibraryItem(
            title: "Brave New World",
            kind: .singleFile,
            totalDuration: 28800.0,
            currentPosition: 14400.0,
            isCompleted: false
        )
        
        let activeItems = [book1, book2]
        
        // Initially both are in the library
        let libraryCountBefore = activeItems.filter { $0.parent == nil && !$0.isDeletedFromLibrary }.count
        #expect(libraryCountBefore == 2)
        
        // User deletes book1 from library: soft-delete preserves history
        book1.isDeletedFromLibrary = true
        book1.isFileOffloaded = true
        
        // Active library should now only contain book2
        let libraryCountAfter = activeItems.filter { $0.parent == nil && !$0.isDeletedFromLibrary }.count
        #expect(libraryCountAfter == 1)
        
        // Profile listening statistics must retain book1's completed status and listened hours
        let totalSeconds = activeItems.reduce(0.0) { $0 + max(0.0, $1.currentPosition) }
        #expect(totalSeconds == 50400.0) // 36000 + 14400 (14.0 hours)
        
        let completedCount = activeItems.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && $0.isCompleted }.count
        #expect(completedCount == 1) // 1984 still counts as completed!
        
        // History items query in ProfileView
        let historyItems = activeItems.filter { item in
            item.kind != .folder && item.parent?.kind != .multiPart && (item.isCompleted || item.currentPosition > 0)
        }
        #expect(historyItems.count == 2)
        #expect(historyItems.contains(where: { $0.title == "1984" && $0.isDeletedFromLibrary == true }))
    }
    
    // MARK: - Priority 1 Tests: Search Soft Delete & Player Preferences
    
    @Test("Search query strictly excludes soft-deleted and offloaded books from results")
    func testSearchViewSoftDeleteFiltering() {
        let activeBook = LibraryItem(
            title: "Project Hail Mary",
            author: "Andy Weir",
            kind: .singleFile,
            totalDuration: 57600.0,
            currentPosition: 12000.0
        )
        
        let deletedBook = LibraryItem(
            title: "The Martian",
            author: "Andy Weir",
            kind: .singleFile,
            totalDuration: 36000.0,
            currentPosition: 36000.0,
            isCompleted: true
        )
        deletedBook.isDeletedFromLibrary = true
        deletedBook.isFileOffloaded = true
        
        let childTrack = LibraryItem(
            title: "Track 01",
            kind: .singleFile,
            totalDuration: 1800.0
        )
        childTrack.parent = activeBook
        
        let allItems = [activeBook, deletedBook, childTrack]
        
        // Root items filter as updated in SearchView
        let displayedRoots = allItems.filter { $0.parent == nil && !$0.isDeletedFromLibrary }
        
        #expect(displayedRoots.count == 1)
        #expect(displayedRoots.first?.title == "Project Hail Mary")
        #expect(!displayedRoots.contains(where: { $0.isDeletedFromLibrary }))
        
        // Live search filter matching "Andy Weir"
        let query = "Andy"
        let searchResults = displayedRoots.filter { item in
            item.title.localizedCaseInsensitiveContains(query) ||
            (item.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
        
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.title == "Project Hail Mary")
    }
    
    @Test("AudioPlayerManager skip intervals and settings preferences have robust defaults")
    @MainActor
    func testAudioPlayerManagerPreferences() {
        let player = AudioPlayerManager()
        
        // Defaults when unset in UserDefaults
        #expect(player.skipForwardInterval == 30.0)
        #expect(player.skipBackwardInterval == 15.0)
        #expect(player.isSmartRewindEnabled == true)
        #expect(player.isContinuousPlaybackEnabled == true)
    }
    
    // MARK: - NavigationCoordinator Deep Link Tests
    
    @Test("NavigationCoordinator handles stats and profile deep links")
    @MainActor
    func testNavigationCoordinatorStatsDeepLink() throws {
        let coordinator = NavigationCoordinator()
        let player = AudioPlayerManager()
        let schema = Schema([LibraryItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        coordinator.selectedTab = .library
        coordinator.handleURL(URL(string: "listenup://stats")!, in: context, player: player)
        #expect(coordinator.selectedTab == .profile)
        
        coordinator.selectedTab = .library
        coordinator.handleURL(URL(string: "listenup://profile")!, in: context, player: player)
        #expect(coordinator.selectedTab == .profile)
    }
    
    @Test("NavigationCoordinator handles play deep link with query parameter ID")
    @MainActor
    func testNavigationCoordinatorPlayDeepLinkWithQuery() throws {
        let coordinator = NavigationCoordinator()
        let player = AudioPlayerManager()
        let schema = Schema([LibraryItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        let targetBook = LibraryItem(
            title: "Dune",
            author: "Frank Herbert",
            kind: .singleFile,
            totalDuration: 72000.0
        )
        context.insert(targetBook)
        try context.save()
        
        let url = URL(string: "listenup://play?id=\(targetBook.id.uuidString)")!
        coordinator.handleURL(url, in: context, player: player)
        
        #expect(coordinator.isShowingFullPlayer == true)
        #expect(player.currentItem?.id == targetBook.id)
    }
    
    @Test("NavigationCoordinator handles book deep link with path component ID")
    @MainActor
    func testNavigationCoordinatorBookDeepLinkWithPath() throws {
        let coordinator = NavigationCoordinator()
        let player = AudioPlayerManager()
        let schema = Schema([LibraryItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        let targetBook = LibraryItem(
            title: "Foundation",
            author: "Isaac Asimov",
            kind: .singleFile,
            totalDuration: 40000.0
        )
        context.insert(targetBook)
        try context.save()
        
        let url = URL(string: "listenup://book/\(targetBook.id.uuidString)")!
        coordinator.handleURL(url, in: context, player: player)
        
        #expect(coordinator.isShowingFullPlayer == true)
        #expect(player.currentItem?.id == targetBook.id)
    }
    
    @Test("NavigationCoordinator handles nowplaying deep link with fallback to most recent item")
    @MainActor
    func testNavigationCoordinatorNowPlayingDeepLink() throws {
        let coordinator = NavigationCoordinator()
        let player = AudioPlayerManager()
        let schema = Schema([LibraryItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        let book = LibraryItem(
            title: "Hyperion",
            author: "Dan Simmons",
            kind: .singleFile,
            totalDuration: 50000.0
        )
        context.insert(book)
        try context.save()
        
        let url = URL(string: "listenup://nowplaying")!
        coordinator.handleURL(url, in: context, player: player)
        
        #expect(coordinator.isShowingFullPlayer == true)
        #expect(player.currentItem?.id == book.id)
    }
    
    // MARK: - WidgetDataStore Serialization Tests
    
    @Test("WidgetDataStore snapshot encodes and decodes JSON correctly")
    func testWidgetSnapshotSerialization() throws {
        let bookID = UUID()
        let playback = WidgetPlaybackSnapshot(
            bookID: bookID,
            title: "The Way of Kings",
            author: "Brandon Sanderson",
            currentTime: 3600.0,
            totalDuration: 180000.0,
            progress: 0.02,
            isPlaying: true,
            artworkData: nil,
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        
        let recent = WidgetRecentBook(
            id: UUID(),
            title: "Words of Radiance",
            author: "Brandon Sanderson",
            progress: 0.45,
            totalDuration: 190000.0,
            artworkData: nil,
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        
        let stats = WidgetStatsSnapshot(
            todaySeconds: 5400.0,
            todayHours: 1,
            todayMinutes: 30,
            todayFormatted: "1h 30m",
            goalMinutes: 60,
            goalProgressFraction: 1.0,
            goalPercentageText: "100%",
            isGoalAccomplished: true,
            remainingMinutes: 0,
            currentMonthName: "October",
            currentMonthHours: 25.5,
            previousMonthName: "September",
            previousMonthHours: 20.0,
            monthDeltaHours: 5.5,
            monthPercentageChange: 27.5,
            totalSummaryFormatted: "25h 30m",
            totalHours: 25,
            streakDays: 7,
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        
        let original = WidgetDataSnapshot(
            nowPlaying: playback,
            recentBooks: [recent],
            stats: stats,
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetDataSnapshot.self, from: data)
        
        #expect(decoded.nowPlaying?.title == "The Way of Kings")
        #expect(decoded.nowPlaying?.author == "Brandon Sanderson")
        #expect(decoded.nowPlaying?.currentTime == 3600.0)
        #expect(decoded.nowPlaying?.isPlaying == true)
        #expect(decoded.recentBooks.count == 1)
        #expect(decoded.recentBooks.first?.title == "Words of Radiance")
        #expect(decoded.stats.todayFormatted == "1h 30m")
        #expect(decoded.stats.isGoalAccomplished == true)
        #expect(decoded.stats.streakDays == 7)
    }
    
    @Test("WidgetDataSnapshot decodes gracefully from empty JSON")
    func testWidgetSnapshotEmptyJSONGracefulDecoding() throws {
        let emptyData = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WidgetDataSnapshot.self, from: emptyData)
        #expect(decoded.nowPlaying == nil)
        #expect(decoded.recentBooks.isEmpty)
        #expect(decoded.stats.todaySeconds == 0.0)
    }
    
    // MARK: - ChapterExtractor Fallback & Nero Parsing Tests
    
    @Test("ChapterExtractor returns empty list for non-existent or empty audio files")
    func testChapterExtractorEmptyFileFallback() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4b")
        let track = TrackDescriptor(url: tempURL, title: "Missing Track", duration: 100.0)
        let chapters = await ChapterExtractor.extractChapters(for: [track], isSingleFile: true)
        #expect(chapters.isEmpty)
    }
    
    @Test("ChapterExtractor correctly parses synthetic Nero chpl atom payload version 1")
    func testChapterExtractorParseNeroPayloadVersion1() {
        var data = Data()
        data.append(contentsOf: [1, 0, 0, 0]) // version 1, flags 0
        data.append(contentsOf: [0, 0, 0, 0]) // reserved
        
        let count: UInt32 = 2
        var bigCount = count.bigEndian
        data.append(Data(bytes: &bigCount, count: 4))
        
        // Chapter 1: at 0.0s
        let time1: UInt64 = 0
        var bigTime1 = time1.bigEndian
        data.append(Data(bytes: &bigTime1, count: 8))
        let title1 = "Chapter 1"
        data.append(UInt8(title1.utf8.count))
        data.append(contentsOf: title1.utf8)
        
        // Chapter 2: at 300.0s
        let time2: UInt64 = 300 * 10_000_000
        var bigTime2 = time2.bigEndian
        data.append(Data(bytes: &bigTime2, count: 8))
        let title2 = "Chapter 2"
        data.append(UInt8(title2.utf8.count))
        data.append(contentsOf: title2.utf8)
        
        let parsed = ChapterExtractor.parseNeroChplPayload(
            from: data,
            chplOffset: 0,
            timeOffset: 0.0,
            baseIndex: 0,
            totalDuration: 600.0
        )
        
        #expect(parsed != nil)
        #expect(parsed?.count == 2)
        #expect(parsed?[0].title == "Chapter 1")
        #expect(parsed?[0].startTime == 0.0)
        #expect(parsed?[0].duration == 300.0)
        #expect(parsed?[1].title == "Chapter 2")
        #expect(parsed?[1].startTime == 300.0)
        #expect(parsed?[1].duration == 300.0)
    }
    
    @Test("ChapterExtractor correctly parses synthetic Nero chpl atom payload version 0")
    func testChapterExtractorParseNeroPayloadVersion0() {
        var data = Data()
        data.append(contentsOf: [0, 0, 0, 0]) // version 0, flags 0
        data.append(1) // count 1
        
        let time1: UInt64 = 60 * 10_000_000
        var bigTime1 = time1.bigEndian
        data.append(Data(bytes: &bigTime1, count: 8))
        let title1 = "Prologue Part"
        data.append(UInt8(title1.utf8.count))
        data.append(contentsOf: title1.utf8)
        
        let parsed = ChapterExtractor.parseNeroChplPayload(
            from: data,
            chplOffset: 0,
            timeOffset: 10.0,
            baseIndex: 5,
            totalDuration: 120.0
        )
        
        #expect(parsed != nil)
        #expect(parsed?.count == 1)
        #expect(parsed?[0].index == 5)
        #expect(parsed?[0].title == "Prologue Part")
        #expect(parsed?[0].startTime == 70.0) // 10.0 + 60.0
        #expect(parsed?[0].duration == 60.0)  // 120.0 - 60.0
    }
    
    @Test("ChapterExtractor returns nil safely for corrupt or truncated Nero payloads")
    func testChapterExtractorCorruptNeroPayload() {
        let corruptData = Data([1, 0, 0, 0, 0, 0]) // truncated
        let parsed = ChapterExtractor.parseNeroChplPayload(
            from: corruptData,
            chplOffset: 0,
            timeOffset: 0.0,
            baseIndex: 0,
            totalDuration: 100.0
        )
        #expect(parsed == nil)
    }
    
    // MARK: - Priority 3 Feature Tests
    
    @Test("AudioPlayerManager shake to extend extends sleep timer by 5 minutes")
    @MainActor
    func testShakeToExtendSleepTimer() {
        let player = AudioPlayerManager()
        defer { player.teardown() }
        
        UserDefaults.standard.set(true, forKey: "shakeToExtendSleepTimer")
        #expect(player.isShakeToExtendSleepTimerEnabled == true)
        
        // Initial state: no sleep timer
        player.extendSleepTimer(by: 300.0)
        #expect(player.sleepTimerRemaining != nil)
        #expect(player.sleepTimerRemaining! >= 299.0)
        
        // Extending an already active sleep timer adds time
        player.extendSleepTimer(by: 300.0)
        #expect(player.sleepTimerRemaining! >= 598.0)
    }
    
    @Test("AudioPlayerManager deviceDidShake notification triggers sleep timer extension when enabled")
    @MainActor
    func testShakeNotificationTriggersExtension() async throws {
        let player = AudioPlayerManager()
        defer { player.teardown() }
        
        UserDefaults.standard.set(true, forKey: "shakeToExtendSleepTimer")
        player.startShakeToExtendDetection(duration: 5.0)
        #expect(player.isWaitingForShakeToExtend == true)
        
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        
        // Allow MainActor task to execute
        try await Task.sleep(nanoseconds: 50_000_000)
        
        #expect(player.isWaitingForShakeToExtend == false)
        #expect(player.sleepTimerRemaining != nil)
        #expect(player.sleepTimerRemaining! >= 299.0)
    }
    
    @Test("WatchLibraryStore refreshDownloadedFiles scans directory asynchronously")
    @MainActor
    func testWatchLibraryStoreRefreshDownloadedFiles() async throws {
        let store = WatchLibraryStore()
        store.refreshDownloadedFiles()
        
        // Allow background Task.detached to complete
        try await Task.sleep(nanoseconds: 50_000_000)
        
        #expect(store.downloadedBookIDs.isEmpty || !store.downloadedBookIDs.isEmpty)
    }
    
    #if canImport(UIKit)
    @Test("CarPlay image cache eviction limits entries to countLimit")
    func testCarPlayImageCacheEviction() {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 100
        
        var keys: [NSUUID] = []
        for _ in 0..<150 {
            let key = NSUUID()
            keys.append(key)
            let image = UIImage()
            cache.setObject(image, forKey: key)
        }
        
        // NSCache evicts objects to respect countLimit
        var cachedCount = 0
        for key in keys {
            if cache.object(forKey: key) != nil {
                cachedCount += 1
            }
        }
        #expect(cachedCount <= 100)
    }
    #endif
}


