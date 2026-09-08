import Foundation
import AVFoundation
import SwiftData

/// Intermediate thread-safe DTO describing an imported file or folder tree
/// before persistence into SwiftData.
public struct ImportedItemDTO: Sendable {
    public let id: UUID
    public let title: String
    public let author: String?
    public let kind: ItemKind
    public let relativePath: String?
    public let totalDuration: Double
    public let sortOrder: Int
    public let artworkData: Data?
    public let children: [ImportedItemDTO]
    
    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        kind: ItemKind,
        relativePath: String? = nil,
        totalDuration: Double = 0.0,
        sortOrder: Int = 0,
        artworkData: Data? = nil,
        children: [ImportedItemDTO] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kind = kind
        self.relativePath = relativePath
        self.totalDuration = totalDuration
        self.sortOrder = sortOrder
        self.artworkData = artworkData
        self.children = children
    }
}

/// Errors encountered during the file import pipeline.
public enum FileImporterError: LocalizedError, Sendable {
    case securityScopeAccessDenied
    case invalidFileType
    case documentsDirectoryNotFound
    case fileTransferFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .securityScopeAccessDenied:
            return "Failed to obtain security-scoped access to the selected resource."
        case .invalidFileType:
            return "The selected file type is not a supported audio format or folder."
        case .documentsDirectoryNotFound:
            return "Application Documents directory could not be resolved."
        case .fileTransferFailed(let reason):
            return "Failed to copy media into the application sandbox: \(reason)"
        }
    }
}

/// Service that securely imports audio files and folders off the main thread,
/// parses audio metadata via `AVURLAsset`, and builds SwiftData `LibraryItem` hierarchies.
public actor FileImporterService {
    
    public static let shared = FileImporterService()
    
    /// Supported audio extensions.
    public static let supportedAudioExtensions: Set<String> = [
        "m4b", "m4a", "mp3", "aac", "wav", "flac", "aif", "aiff"
    ]
    
    private init() {}
    
    // MARK: - Primary Public Import Entry Points
    
    /// Imports a security-scoped URL (file or folder), copying contents into `Documents/Audiobooks/`
    /// and returning the Sendable hierarchy description.
    public func processImport(from sourceURL: URL) async throws -> ImportedItemDTO {
        // 1. Security-scoped resource access
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw FileImporterError.securityScopeAccessDenied
        }
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw FileImporterError.documentsDirectoryNotFound
        }
        
        // Base destination directory in sandbox
        let audiobooksDirectory = documentsURL.appendingPathComponent("Audiobooks", isDirectory: true)
        if !fileManager.fileExists(atPath: audiobooksDirectory.path) {
            try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
        }
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw FileImporterError.fileTransferFailed("Source does not exist")
        }
        
        if isDir.boolValue {
            // Import directory recursively
            return try await processDirectory(
                sourceDir: sourceURL,
                sandboxBaseURL: documentsURL,
                destinationParentDir: audiobooksDirectory
            )
        } else {
            // Import single audio file
            return try await processSingleFile(
                sourceFile: sourceURL,
                sandboxBaseURL: documentsURL,
                destinationParentDir: audiobooksDirectory
            )
        }
    }
    
    // MARK: - Single Audio File Processing
    
    private func processSingleFile(
        sourceFile: URL,
        sandboxBaseURL: URL,
        destinationParentDir: URL
    ) async throws -> ImportedItemDTO {
        let fileExtension = sourceFile.pathExtension.lowercased()
        guard Self.supportedAudioExtensions.contains(fileExtension) else {
            throw FileImporterError.invalidFileType
        }
        
        let fileName = sourceFile.lastPathComponent
        let destinationFile = destinationParentDir.appendingPathComponent(fileName)
        
        // If file already exists, make unique name
        let finalDestination = try copyItemSafely(from: sourceFile, to: destinationFile)
        let relativePath = computeRelativePath(for: finalDestination, relativeTo: sandboxBaseURL)
        
        // Parse metadata asynchronously
        let metadata = await extractMetadata(for: finalDestination)
        
        let itemTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? metadata.title!
            : sourceFile.deletingPathExtension().lastPathComponent
        
        return ImportedItemDTO(
            id: UUID(),
            title: itemTitle,
            author: metadata.author,
            kind: .singleFile,
            relativePath: relativePath,
            totalDuration: metadata.duration,
            sortOrder: 0,
            artworkData: metadata.artworkData,
            children: []
        )
    }
    
    // MARK: - Directory Recursive Processing
    
    private func processDirectory(
        sourceDir: URL,
        sandboxBaseURL: URL,
        destinationParentDir: URL
    ) async throws -> ImportedItemDTO {
        let fileManager = FileManager.default
        let folderName = sourceDir.lastPathComponent
        let destinationFolder = destinationParentDir.appendingPathComponent(folderName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: destinationFolder.path) {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        var audioFiles: [URL] = []
        var subDirectories: [URL] = []
        
        for item in contents {
            var isSubDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isSubDir) {
                if isSubDir.boolValue {
                    subDirectories.append(item)
                } else if Self.supportedAudioExtensions.contains(item.pathExtension.lowercased()) {
                    audioFiles.append(item)
                }
            }
        }
        
        // Sort items naturally
        audioFiles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        subDirectories.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        // Process child audio files
        var childAudioDTOs: [ImportedItemDTO] = []
        for (index, file) in audioFiles.enumerated() {
            var childDTO = try await processSingleFile(
                sourceFile: file,
                sandboxBaseURL: sandboxBaseURL,
                destinationParentDir: destinationFolder
            )
            // Assign sequential sortOrder
            childDTO = ImportedItemDTO(
                id: childDTO.id,
                title: childDTO.title,
                author: childDTO.author,
                kind: childDTO.kind,
                relativePath: childDTO.relativePath,
                totalDuration: childDTO.totalDuration,
                sortOrder: index,
                artworkData: childDTO.artworkData,
                children: childDTO.children
            )
            childAudioDTOs.append(childDTO)
        }
        
        // Process subdirectories recursively
        var childSubDirDTOs: [ImportedItemDTO] = []
        for (index, subDir) in subDirectories.enumerated() {
            var subDirDTO = try await processDirectory(
                sourceDir: subDir,
                sandboxBaseURL: sandboxBaseURL,
                destinationParentDir: destinationFolder
            )
            subDirDTO = ImportedItemDTO(
                id: subDirDTO.id,
                title: subDirDTO.title,
                author: subDirDTO.author,
                kind: subDirDTO.kind,
                relativePath: subDirDTO.relativePath,
                totalDuration: subDirDTO.totalDuration,
                sortOrder: childAudioDTOs.count + index,
                artworkData: subDirDTO.artworkData,
                children: subDirDTO.children
            )
            childSubDirDTOs.append(subDirDTO)
        }
        
        let allChildren = childAudioDTOs + childSubDirDTOs
        let totalDuration = allChildren.reduce(0.0) { $0 + $1.totalDuration }
        
        // Common metadata from children (e.g. artwork from the first track)
        let representativeArtwork = allChildren.compactMap { $0.artworkData }.first
        let representativeAuthor = allChildren.compactMap { $0.author }.first
        
        // Heuristic: If this folder contains only audio tracks (and no nested folders),
        // treat it as a continuous `.multiPart` audiobook!
        // If it has subdirectories (e.g. "Pimsleur" containing levels), treat it as a `.folder`.
        let isMultiPart = subDirectories.isEmpty && !childAudioDTOs.isEmpty
        let itemKind: ItemKind = isMultiPart ? .multiPart : .folder
        
        let relativeFolder = computeRelativePath(for: destinationFolder, relativeTo: sandboxBaseURL)
        
        return ImportedItemDTO(
            id: UUID(),
            title: folderName,
            author: representativeAuthor,
            kind: itemKind,
            relativePath: relativeFolder,
            totalDuration: totalDuration,
            sortOrder: 0,
            artworkData: representativeArtwork,
            children: allChildren
        )
    }
    
    // MARK: - Audio Metadata Extraction via AVURLAsset
    
    private struct ExtractedMetadata: Sendable {
        let title: String?
        let author: String?
        let duration: Double
        let artworkData: Data?
    }
    
    private func extractMetadata(for fileURL: URL) async -> ExtractedMetadata {
        let asset = AVURLAsset(url: fileURL)
        
        // Load duration asynchronously
        var durationSeconds: Double = 0.0
        if let duration = try? await asset.load(.duration) {
            let seconds = duration.seconds
            if !seconds.isNaN && !seconds.isInfinite && seconds > 0 {
                durationSeconds = seconds
            }
        }
        
        // Load common metadata
        var extractedTitle: String?
        var extractedAuthor: String?
        var extractedArtwork: Data?
        
        if let metadataItems = try? await asset.load(.commonMetadata) {
            for item in metadataItems {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if extractedTitle == nil {
                        extractedTitle = try? await item.load(.stringValue)
                    }
                case .commonKeyArtist, .commonKeyAuthor:
                    if extractedAuthor == nil {
                        extractedAuthor = try? await item.load(.stringValue)
                    }
                case .commonKeyArtwork:
                    if extractedArtwork == nil {
                        extractedArtwork = try? await item.load(.dataValue)
                    }
                default:
                    break
                }
            }
        }
        
        return ExtractedMetadata(
            title: extractedTitle,
            author: extractedAuthor,
            duration: durationSeconds,
            artworkData: extractedArtwork
        )
    }
    
    // MARK: - File System Helpers
    
    private func copyItemSafely(from source: URL, to destination: URL) throws -> URL {
        let fileManager = FileManager.default
        var targetURL = destination
        
        if fileManager.fileExists(atPath: targetURL.path) {
            // Create unique suffix
            let baseName = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            let uniqueName = "\(baseName)_\(UUID().uuidString.prefix(6)).\(ext)"
            targetURL = destination.deletingLastPathComponent().appendingPathComponent(uniqueName)
        }
        
        try fileManager.copyItem(at: source, to: targetURL)
        return targetURL
    }
    
    private func computeRelativePath(for url: URL, relativeTo base: URL) -> String {
        let baseStandard = base.resolvingSymlinksInPath().standardizedFileURL.path
        let urlStandard = url.resolvingSymlinksInPath().standardizedFileURL.path
        
        if urlStandard.hasPrefix(baseStandard) {
            var rel = String(urlStandard.dropFirst(baseStandard.count))
            if rel.hasPrefix("/") {
                rel.removeFirst()
            }
            return rel
        }
        
        if let range = url.path.range(of: "Audiobooks/") {
            return String(url.path[range.lowerBound...])
        }
        
        return url.lastPathComponent
    }
}

// MARK: - SwiftData MainActor Persistence Bridge

extension FileImporterService {
    
    /// Converts an `ImportedItemDTO` tree into SwiftData `LibraryItem` entities and saves to the context.
    @MainActor
    public static func persist(dto: ImportedItemDTO, into context: ModelContext, parent: LibraryItem? = nil) -> LibraryItem {
        let item = LibraryItem(
            id: dto.id,
            title: dto.title,
            author: dto.author,
            kind: dto.kind,
            relativePath: dto.relativePath,
            totalDuration: dto.totalDuration,
            currentPosition: 0.0,
            isCompleted: false,
            sortOrder: dto.sortOrder,
            lastUpdated: Date(),
            artworkData: dto.artworkData,
            parent: parent
        )
        
        context.insert(item)
        
        for childDTO in dto.children {
            let childItem = persist(dto: childDTO, into: context, parent: item)
            if item.children == nil {
                item.children = []
            }
            item.children?.append(childItem)
        }
        
        item.recalculateDurations()
        try? context.save()
        
        return item
    }
    
    /// Safely deletes the physical audio file or folder from the application's sandbox Documents directory.
    public static func deletePhysicalFiles(for item: LibraryItem) {
        let fileManager = FileManager.default
        var urlsToRemove: Set<URL> = []
        
        // Main item URL (single file or parent folder)
        if let mainURL = item.resolvedURL() {
            urlsToRemove.insert(mainURL)
        }
        
        // Also collect child track URLs in case of multi-part or nested items
        for track in item.playableTracks {
            if let trackURL = track.resolvedURL() {
                urlsToRemove.insert(trackURL)
            }
        }
        
        for url in urlsToRemove {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    print("[FileImporterService] Successfully deleted file/folder at: \(url.path)")
                } catch {
                    print("[FileImporterService] Failed to delete file at \(url.path): \(error.localizedDescription)")
                }
                
                // If parent folder was dedicated to this item and is now empty, clean it up
                let parentDir = url.deletingLastPathComponent()
                let parentName = parentDir.lastPathComponent
                if parentName != "Audiobooks" && parentName != "Documents" && fileManager.fileExists(atPath: parentDir.path) {
                    if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir.path), contents.isEmpty {
                        try? fileManager.removeItem(at: parentDir)
                    }
                }
            }
        }
    }
}
