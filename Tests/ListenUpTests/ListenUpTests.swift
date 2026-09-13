import Testing
import Foundation
import SwiftData
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
}
