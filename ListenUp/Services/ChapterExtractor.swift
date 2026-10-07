import Foundation
import AVFoundation

/// Thread-safe Sendable descriptor of an audio track used for background metadata extraction.
public struct TrackDescriptor: Sendable {
    public let url: URL?
    public let title: String
    public let duration: Double
    public let startVirtualTime: Double
    
    public init(
        url: URL?,
        title: String,
        duration: Double,
        startVirtualTime: Double = 0.0
    ) {
        self.url = url
        self.title = title
        self.duration = duration
        self.startVirtualTime = startVirtualTime
    }
}

/// Background service for extracting embedded chapter metadata from audio files
/// (QuickTime text tracks, Nero chpl atoms) and synthesizing virtual chapters for multi-part audiobooks.
public enum ChapterExtractor: Sendable {
    
    /// Extracts discrete chapter marks for a collection of track descriptors off the main thread.
    public static func extractChapters(
        for tracks: [TrackDescriptor],
        isSingleFile: Bool
    ) async -> [ChapterInfo] {
        if isSingleFile, let singleTrack = tracks.first {
            return await extractSingleFileChapters(
                fileURL: singleTrack.url,
                fallbackDuration: singleTrack.duration,
                timeOffset: 0.0,
                baseIndex: 0
            )
        }
        
        var allChapters: [ChapterInfo] = []
        var nextIndex = 0
        
        for (idx, track) in tracks.enumerated() {
            let trackChapters = await extractSingleFileChapters(
                fileURL: track.url,
                fallbackDuration: track.duration,
                timeOffset: track.startVirtualTime,
                baseIndex: nextIndex
            )
            
            if !trackChapters.isEmpty {
                allChapters.append(contentsOf: trackChapters)
                nextIndex += trackChapters.count
            } else {
                // Fallback to track segment itself as a chapter
                let synthesized = ChapterInfo(
                    id: UUID(),
                    index: nextIndex,
                    title: track.title.isEmpty ? "Part \(idx + 1)" : track.title,
                    startTime: track.startVirtualTime,
                    duration: track.duration
                )
                allChapters.append(synthesized)
                nextIndex += 1
            }
        }
        
        return allChapters
    }
    
    // MARK: - Single Audio File Extraction (M4A / M4B / QuickTime / Nero)
    
    private static func extractSingleFileChapters(
        fileURL: URL?,
        fallbackDuration: Double,
        timeOffset: Double,
        baseIndex: Int
    ) async -> [ChapterInfo] {
        guard let url = fileURL else {
            print("[ChapterExtractor] Cannot extract chapters: file URL is nil")
            return []
        }
        
        print("[ChapterExtractor] Scanning chapters for: \(url.lastPathComponent)")
        let asset = AVURLAsset(url: url)
        
        // Total asset duration for boundary calculation
        var assetDuration: Double = fallbackDuration
        if assetDuration <= 0, let cmDuration = try? await asset.load(.duration) {
            let secs = cmDuration.seconds
            if !secs.isNaN && !secs.isInfinite && secs > 0 {
                assetDuration = secs
            }
        }
        
        // --- STAGE 1: AVFoundation Chapter Metadata Groups ---
        var groups: [AVTimedMetadataGroup] = []
        
        // 1a. Load using availableChapterLocales without key filtering
        if let locales = try? await asset.load(.availableChapterLocales), !locales.isEmpty {
            for locale in locales {
                if let loaded = try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: []),
                   !loaded.isEmpty {
                    groups = loaded
                    print("[ChapterExtractor] Found \(loaded.count) chapters using locale: \(locale.identifier)")
                    break
                }
            }
        }
        
        // 1b. Load using best matching preferred languages
        if groups.isEmpty {
            let languages = Locale.preferredLanguages
            if let loaded = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages),
               !loaded.isEmpty {
                groups = loaded
                print("[ChapterExtractor] Found \(loaded.count) chapters using preferred languages")
            }
        }
        
        // 1c. Load using Locale.current without key filtering
        if groups.isEmpty {
            if let loaded = try? await asset.loadChapterMetadataGroups(
                withTitleLocale: Locale.current,
                containingItemsWithCommonKeys: []
            ), !loaded.isEmpty {
                groups = loaded
                print("[ChapterExtractor] Found \(loaded.count) chapters using Locale.current")
            }
        }
        
        // 1d. Load using empty locale without key filtering
        if groups.isEmpty {
            if let loaded = try? await asset.loadChapterMetadataGroups(
                withTitleLocale: Locale(identifier: ""),
                containingItemsWithCommonKeys: []
            ), !loaded.isEmpty {
                groups = loaded
                print("[ChapterExtractor] Found \(loaded.count) chapters using empty locale")
            }
        }
        
        // 1e. Load using undetermined ("und") locale without key filtering
        if groups.isEmpty {
            if let loaded = try? await asset.loadChapterMetadataGroups(
                withTitleLocale: Locale(identifier: "und"),
                containingItemsWithCommonKeys: []
            ), !loaded.isEmpty {
                groups = loaded
                print("[ChapterExtractor] Found \(loaded.count) chapters using 'und' locale")
            }
        }
        
        // If AVFoundation groups found, convert them to ChapterInfo
        if !groups.isEmpty {
            var result: [ChapterInfo] = []
            result.reserveCapacity(groups.count)
            
            for (idx, group) in groups.enumerated() {
                let rawStart = group.timeRange.start.seconds
                let startSeconds = (rawStart.isNaN || rawStart.isInfinite || rawStart < 0) ? 0.0 : rawStart
                
                var durationSeconds = group.timeRange.duration.seconds
                if durationSeconds.isNaN || durationSeconds.isInfinite || durationSeconds <= 0 {
                    if idx + 1 < groups.count {
                        let nextStart = groups[idx + 1].timeRange.start.seconds
                        if !nextStart.isNaN && !nextStart.isInfinite && nextStart > startSeconds {
                            durationSeconds = nextStart - startSeconds
                        }
                    } else if assetDuration > startSeconds {
                        durationSeconds = assetDuration - startSeconds
                    } else {
                        durationSeconds = 0.0
                    }
                }
                
                // Extract chapter title from items (trying stringValue, then dataValue / QuickTime text)
                var chapterTitle: String? = nil
                for metadataItem in group.items {
                    if let str = try? await metadataItem.load(.stringValue),
                       !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chapterTitle = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                    if let data = try? await metadataItem.load(.dataValue), !data.isEmpty {
                        if let str = parseQuickTimeText(data) {
                            chapterTitle = str
                            break
                        }
                    }
                }
                
                let finalTitle = (chapterTitle != nil && !chapterTitle!.isEmpty)
                    ? chapterTitle!
                    : "Chapter \(idx + 1)"
                
                let chapter = ChapterInfo(
                    id: UUID(),
                    index: baseIndex + idx,
                    title: finalTitle,
                    startTime: timeOffset + startSeconds,
                    duration: durationSeconds
                )
                result.append(chapter)
            }
            
            print("[ChapterExtractor] Successfully parsed \(result.count) chapters via AVFoundation for \(url.lastPathComponent)")
            return result
        }
        
        // --- STAGE 2: Fallback to Nero chpl atom parser ---
        if let neroChapters = parseNeroChapters(from: url, timeOffset: timeOffset, baseIndex: baseIndex, totalDuration: assetDuration),
           !neroChapters.isEmpty {
            print("[ChapterExtractor] Successfully parsed \(neroChapters.count) chapters via Nero chpl atom for \(url.lastPathComponent)")
            return neroChapters
        }
        
        print("[ChapterExtractor] No chapter tracks or Nero atoms found in: \(url.lastPathComponent)")
        return []
    }
    
    // MARK: - QuickTime Text Sample Parser
    
    private static func parseQuickTimeText(_ data: Data) -> String? {
        // QuickTime text samples often prepend a 2-byte big-endian text length
        if data.count >= 2 {
            let len = (Int(data[0]) << 8) | Int(data[1])
            if len > 0 && len <= data.count - 2 {
                let textData = data.subdata(in: 2..<(2 + len))
                if let str = String(data: textData, encoding: .utf8) ?? String(data: textData, encoding: .macOSRoman) {
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        
        // Direct UTF-8 / UTF-16
        if let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        
        return nil
    }
    
    // MARK: - Nero chpl Atom Parser
    
    static func parseNeroChapters(
        from url: URL,
        timeOffset: Double,
        baseIndex: Int,
        totalDuration: Double
    ) -> [ChapterInfo]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        
        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
        } catch {
            return nil
        }
        
        var currentOffset: UInt64 = 0
        while currentOffset + 8 <= fileSize {
            do {
                try handle.seek(toOffset: currentOffset)
                guard let headerData = try handle.read(upToCount: 8), headerData.count == 8 else {
                    break
                }
                
                let boxSize32 = headerData.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                let boxType = String(decoding: headerData.suffix(4), as: UTF8.self)
                
                var boxSize: UInt64 = UInt64(boxSize32)
                var headerSize: UInt64 = 8
                
                if boxSize32 == 1 {
                    // Extended 64-bit size
                    guard let extData = try handle.read(upToCount: 8), extData.count == 8 else {
                        break
                    }
                    boxSize = extData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                    headerSize = 16
                } else if boxSize32 == 0 {
                    // Extends to end of file
                    boxSize = fileSize - currentOffset
                }
                
                guard boxSize >= headerSize else {
                    break
                }
                
                // moov or udta contain metadata boxes including nero chpl
                if boxType == "moov" || boxType == "udta" {
                    let payloadSize = Int(min(boxSize - headerSize, 50 * 1024 * 1024))
                    try handle.seek(toOffset: currentOffset + headerSize)
                    if let payloadData = try handle.read(upToCount: payloadSize),
                       let chplRange = payloadData.range(of: Data("chpl".utf8)) {
                        return parseNeroChplPayload(
                            from: payloadData,
                            chplOffset: chplRange.upperBound,
                            timeOffset: timeOffset,
                            baseIndex: baseIndex,
                            totalDuration: totalDuration
                        )
                    }
                }
                
                // Advance past this atom (efficiently skipping mdat media payload)
                currentOffset += boxSize
            } catch {
                break
            }
        }
        
        // Fallback for non-standard atom structures on smaller files (<= 15MB)
        if fileSize <= 15 * 1024 * 1024,
           let smallData = try? Data(contentsOf: url, options: .mappedIfSafe),
           let chplRange = smallData.range(of: Data("chpl".utf8)) {
            return parseNeroChplPayload(
                from: smallData,
                chplOffset: chplRange.upperBound,
                timeOffset: timeOffset,
                baseIndex: baseIndex,
                totalDuration: totalDuration
            )
        }
        
        return nil
    }
    
    static func parseNeroChplPayload(
        from data: Data,
        chplOffset: Int,
        timeOffset: Double,
        baseIndex: Int,
        totalDuration: Double
    ) -> [ChapterInfo]? {
        guard chplOffset <= data.count else { return nil }
        let payload = Data(data[chplOffset...])
        guard payload.count >= 4 else { return nil }
        
        let version = payload[0]
        var offset = 4 // skip version (1 byte) + flags (3 bytes)
        
        var parsed: [(title: String, startTime: Double)] = []
        
        if version == 1 {
            guard offset + 8 <= payload.count else { return nil }
            offset += 4 // skip 4 bytes reserved
            let count = payload[offset..<offset+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            offset += 4
            
            for _ in 0..<count {
                guard offset + 9 <= payload.count else { break }
                let rawTime = payload[offset..<offset+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                offset += 8
                let secs = Double(rawTime) / 10_000_000.0
                
                let titleLen = Int(payload[offset])
                offset += 1
                guard offset + titleLen <= payload.count else { break }
                let str = String(data: payload[offset..<offset+titleLen], encoding: .utf8) ?? ""
                offset += titleLen
                parsed.append((title: str, startTime: secs))
            }
        } else if version == 0 {
            guard offset + 1 <= payload.count else { return nil }
            let count = Int(payload[offset])
            offset += 1
            
            for _ in 0..<count {
                guard offset + 9 <= payload.count else { break }
                let rawTime = payload[offset..<offset+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                offset += 8
                let secs = Double(rawTime) / 10_000_000.0
                
                let titleLen = Int(payload[offset])
                offset += 1
                guard offset + titleLen <= payload.count else { break }
                let str = String(data: payload[offset..<offset+titleLen], encoding: .utf8) ?? ""
                offset += titleLen
                parsed.append((title: str, startTime: secs))
            }
        }
        
        guard !parsed.isEmpty else { return nil }
        
        var result: [ChapterInfo] = []
        for (i, entry) in parsed.enumerated() {
            var dur: Double = 0.0
            if i + 1 < parsed.count {
                dur = max(0.0, parsed[i + 1].startTime - entry.startTime)
            } else if totalDuration > entry.startTime {
                dur = max(0.0, totalDuration - entry.startTime)
            }
            
            let finalTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Chapter \(i + 1)"
                : entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            
            result.append(ChapterInfo(
                id: UUID(),
                index: baseIndex + i,
                title: finalTitle,
                startTime: timeOffset + entry.startTime,
                duration: dur
            ))
        }
        
        return result
    }
}
