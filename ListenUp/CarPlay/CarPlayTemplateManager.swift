#if canImport(CarPlay)
import CarPlay
import UIKit
import SwiftData

/// Template coordinator responsible for managing the CarPlay template hierarchy,
/// library navigation, and audio playback integration for ListenUp.
@MainActor
public final class CarPlayTemplateManager: NSObject {
    
    // MARK: - Dependencies & Core References
    
    private weak var interfaceController: CPInterfaceController?
    private let player = AudioPlayerManager.shared
    private let database = AppDatabase.shared
    
    // MARK: - Root Templates
    
    private var listenNowTemplate: CPListTemplate!
    private var libraryTemplate: CPListTemplate!
    private var tabBarTemplate: CPTabBarTemplate!
    
    // MARK: - Notification Observers & Image Cache
    
    private var playbackObserver: NSObjectProtocol?
    private var contextSaveObserver: NSObjectProtocol?
    private var artworkThumbnailCache: [UUID: UIImage] = [:]
    
    // MARK: - Initialization
    
    public init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
    }
    
    deinit {
        // Observers removed in stop()
    }
    
    // MARK: - Lifecycle Management
    
    /// Starts the CarPlay template hierarchy and registers observers.
    public func start() {
        configureRootTemplates()
        setupNowPlayingTemplate()
        registerObservers()
        refreshAllTemplates()
    }
    
    /// Stops the manager and unregisters all active observers.
    public func stop() {
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        if let observer = contextSaveObserver {
            NotificationCenter.default.removeObserver(observer)
            contextSaveObserver = nil
        }
        CPNowPlayingTemplate.shared.remove(self)
        artworkThumbnailCache.removeAll()
    }
    
    // MARK: - Root Template Setup
    
    private func configureRootTemplates() {
        // 1. Tab 1: Listen Now (In-progress & recent books)
        listenNowTemplate = CPListTemplate(title: "Listen Now", sections: [])
        listenNowTemplate.tabImage = UIImage(systemName: "play.circle.fill")
        listenNowTemplate.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        
        // 2. Tab 2: Library (Full catalog & folder drilling)
        libraryTemplate = CPListTemplate(title: "Library", sections: [])
        libraryTemplate.tabImage = UIImage(systemName: "books.vertical.fill")
        libraryTemplate.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        
        // 3. Tab Bar Root Template
        tabBarTemplate = CPTabBarTemplate(templates: [listenNowTemplate, libraryTemplate])
        interfaceController?.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
    }
    
    private func setupNowPlayingTemplate() {
        let nowPlaying = CPNowPlayingTemplate.shared
        
        // 1. Playback Rate Cycling Button (0.75x -> 1.0x -> 1.25x -> 1.5x -> 1.75x -> 2.0x)
        let rateButton = CPNowPlayingPlaybackRateButton { [weak self] _ in
            self?.player.cyclePlaybackRate()
        }
        
        // 2. Chapters List Button
        let chaptersImage = UIImage(systemName: "list.bullet") ?? UIImage()
        let chaptersButton = CPNowPlayingImageButton(image: chaptersImage) { [weak self] _ in
            self?.showChaptersList()
        }
        
        nowPlaying.updateNowPlayingButtons([rateButton, chaptersButton])
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.add(self)
    }
    
    private func registerObservers() {
        // Live playback state changes (play, pause, chapter changes, speed)
        playbackObserver = NotificationCenter.default.addObserver(
            forName: AudioPlayerManager.playbackStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllTemplates()
            }
        }
        
        // SwiftData updates (new imports, deletions, position sync)
        contextSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllTemplates()
            }
        }
    }
    
    // MARK: - Navigation Bar Helpers
    
    private func makeNowPlayingBarButton() -> CPBarButton {
        let waveformImage = UIImage(systemName: "waveform") ?? UIImage()
        return CPBarButton(image: waveformImage) { [weak self] _ in
            self?.showNowPlaying()
        }
    }
    
    // MARK: - Template Refresh Engine
    
    public func refreshAllTemplates() {
        refreshListenNow()
        refreshLibrary()
    }
    
    private func refreshListenNow() {
        let context = database.mainContext
        
        // Query items currently in progress (currentPosition > 0 and not marked completed)
        let descriptor = FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.parent == nil && $0.currentPosition > 0 && !$0.isCompleted },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        
        let inProgressItems = (try? context.fetch(descriptor)) ?? []
        var sections: [CPListSection] = []
        
        // Section A: Currently Playing (if loaded)
        if let currentItem = player.currentItem {
            let activeRow = makePlayableListItem(
                for: currentItem,
                isCurrentTrack: true
            )
            sections.append(CPListSection(items: [activeRow], header: "Now Playing", sectionIndexTitle: nil))
        }
        
        // Section B: Continue Listening
        let otherItems = inProgressItems.filter { $0.id != player.currentItem?.id }
        if !otherItems.isEmpty {
            let items = otherItems.prefix(12).map { item in
                makePlayableListItem(for: item, isCurrentTrack: false)
            }
            sections.append(CPListSection(items: Array(items), header: "Continue Listening", sectionIndexTitle: nil))
        }
        
        // Fallback placeholder if library is empty or no books in progress
        if sections.isEmpty {
            let emptyItem = CPListItem(
                text: "No Audiobooks in Progress",
                detailText: "Select an audiobook from your Library tab to begin listening.",
                image: UIImage(systemName: "book.closed")
            )
            sections.append(CPListSection(items: [emptyItem]))
        }
        
        listenNowTemplate.updateSections(sections)
    }
    
    private func refreshLibrary() {
        let context = database.mainContext
        
        // Fetch top-level library items
        let descriptor = FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.parent == nil },
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.title, order: .forward)
            ]
        )
        
        let allItems = (try? context.fetch(descriptor)) ?? []
        var sections: [CPListSection] = []
        
        // 1. Folders / Collections
        let folders = allItems.filter { $0.kind == .folder }
        if !folders.isEmpty {
            let folderRows = folders.map { folder -> CPListItem in
                let row = CPListItem(
                    text: folder.title,
                    detailText: "\(folder.sortedChildren.count) items",
                    image: UIImage(systemName: "folder.fill")
                )
                row.accessoryType = .disclosureIndicator
                row.handler = { [weak self] _, completion in
                    self?.showFolder(folder)
                    completion()
                }
                return row
            }
            sections.append(CPListSection(items: folderRows, header: "Collections & Folders", sectionIndexTitle: nil))
        }
        
        // 2. Audiobooks
        let books = allItems.filter { $0.kind != .folder }
        if !books.isEmpty {
            let bookRows = books.map { book in
                makePlayableListItem(
                    for: book,
                    isCurrentTrack: book.id == player.currentItem?.id
                )
            }
            sections.append(CPListSection(items: bookRows, header: "Audiobooks", sectionIndexTitle: nil))
        }
        
        if sections.isEmpty {
            let emptyItem = CPListItem(
                text: "Library is Empty",
                detailText: "Import audiobooks on your iPhone using Files or AirDrop.",
                image: UIImage(systemName: "tray")
            )
            sections.append(CPListSection(items: [emptyItem]))
        }
        
        libraryTemplate.updateSections(sections)
    }
    
    // MARK: - Folder Navigation Drill-down
    
    private func showFolder(_ folder: LibraryItem) {
        let childItems = folder.sortedChildren
        var sections: [CPListSection] = []
        
        let childFolders = childItems.filter { $0.kind == .folder }
        if !childFolders.isEmpty {
            let folderRows = childFolders.map { subFolder -> CPListItem in
                let row = CPListItem(
                    text: subFolder.title,
                    detailText: "\(subFolder.sortedChildren.count) items",
                    image: UIImage(systemName: "folder.fill")
                )
                row.accessoryType = .disclosureIndicator
                row.handler = { [weak self] _, completion in
                    self?.showFolder(subFolder)
                    completion()
                }
                return row
            }
            sections.append(CPListSection(items: folderRows, header: "Sub-folders", sectionIndexTitle: nil))
        }
        
        let childBooks = childItems.filter { $0.kind != .folder }
        if !childBooks.isEmpty {
            let bookRows = childBooks.map { book in
                makePlayableListItem(
                    for: book,
                    isCurrentTrack: book.id == player.currentItem?.id
                )
            }
            sections.append(CPListSection(items: bookRows, header: "Audiobooks", sectionIndexTitle: nil))
        }
        
        let folderTemplate = CPListTemplate(title: folder.title, sections: sections)
        folderTemplate.trailingNavigationBarButtons = [makeNowPlayingBarButton()]
        interfaceController?.pushTemplate(folderTemplate, animated: true, completion: nil)
    }
    
    // MARK: - Playable List Item Factory
    
    private func makePlayableListItem(for item: LibraryItem, isCurrentTrack: Bool) -> CPListItem {
        var detailParts: [String] = []
        if let author = item.author, !author.isEmpty {
            detailParts.append(author)
        }
        
        let remainingSeconds = max(0.0, item.totalDuration - item.currentPosition)
        if remainingSeconds > 0 && item.totalDuration > 0 {
            detailParts.append(TimeFormatting.formatRemainingTimestamp(current: item.currentPosition, total: item.totalDuration) + " remaining")
        } else if item.totalDuration > 0 {
            detailParts.append(item.formattedTotalDuration)
        }
        
        let detailString = detailParts.joined(separator: " • ")
        let listItem = CPListItem(
            text: item.title,
            detailText: detailString,
            image: thumbnailImage(for: item)
        )
        
        // Native CarPlay equalizer icon and progress bar
        listItem.isPlaying = isCurrentTrack && player.isPlaying
        listItem.playbackProgress = CGFloat(item.progress)
        
        listItem.handler = { [weak self] _, completion in
            self?.player.play(item: item)
            self?.showNowPlaying()
            completion()
        }
        
        return listItem
    }
    
    // MARK: - Now Playing & Chapter Presentation
    
    public func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        // Avoid pushing if already top template
        if interfaceController?.topTemplate !== nowPlaying {
            interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }
    
    public func showChaptersList() {
        let chapters = player.chapters
        
        var chapterRows: [CPListItem] = []
        if !chapters.isEmpty {
            chapterRows = chapters.map { chapter in
                let detail = "\(TimeFormatting.formatTimestamp(chapter.startTime)) • \(TimeFormatting.formatTimestamp(chapter.duration))"
                let isCurrentChapter = (player.currentChapter?.id == chapter.id)
                let icon = UIImage(systemName: isCurrentChapter ? "speaker.wave.2.fill" : "bookmark")
                let item = CPListItem(text: chapter.title, detailText: detail, image: icon)
                
                item.isPlaying = isCurrentChapter && player.isPlaying
                
                item.handler = { [weak self] _, completion in
                    self?.player.skipToChapter(chapter)
                    self?.interfaceController?.popTemplate(animated: true, completion: nil)
                    completion()
                }
                return item
            }
        } else if let currentItem = player.currentItem, currentItem.kind == .multiPart {
            // For multi-part audiobooks without embedded markers, each track acts as a chapter
            chapterRows = currentItem.playableTracks.enumerated().map { index, track in
                let detail = track.formattedTotalDuration
                let isCurrent = (player.currentTrackIndex == index)
                let icon = UIImage(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                let item = CPListItem(text: track.title, detailText: detail, image: icon)
                item.isPlaying = isCurrent && player.isPlaying
                
                item.handler = { [weak self] _, completion in
                    if let startVirtualTime = currentItem.segments[safe: index]?.startVirtualTime {
                        self?.player.seek(to: startVirtualTime)
                    }
                    self?.interfaceController?.popTemplate(animated: true, completion: nil)
                    completion()
                }
                return item
            }
        }
        
        if chapterRows.isEmpty {
            let empty = CPListItem(
                text: "No Chapter Marks",
                detailText: "This audiobook has continuous playback.",
                image: UIImage(systemName: "info.circle")
            )
            chapterRows = [empty]
        }
        
        let section = CPListSection(items: chapterRows)
        let chaptersTemplate = CPListTemplate(
            title: player.currentItem?.title ?? "Chapters",
            sections: [section]
        )
        interfaceController?.pushTemplate(chaptersTemplate, animated: true, completion: nil)
    }
    
    // MARK: - CPNowPlayingTemplateObserver
}

extension CarPlayTemplateManager: CPNowPlayingTemplateObserver {
    public nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor [weak self] in
            self?.showChaptersList()
        }
    }
}

extension CarPlayTemplateManager {
    
    // MARK: - Artwork Thumbnail Generation & Caching
    
    private func thumbnailImage(for item: LibraryItem) -> UIImage {
        if let cached = artworkThumbnailCache[item.id] {
            return cached
        }
        
        if let data = item.artworkData,
           let sourceImage = UIImage(data: data) {
            let size = CGSize(width: 60, height: 60)
            let renderer = UIGraphicsImageRenderer(size: size)
            let thumbnail = renderer.image { _ in
                let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
                path.addClip()
                sourceImage.draw(in: CGRect(origin: .zero, size: size))
            }
            artworkThumbnailCache[item.id] = thumbnail
            return thumbnail
        }
        
        let fallback = UIImage(systemName: "book.fill") ?? UIImage()
        artworkThumbnailCache[item.id] = fallback
        return fallback
    }
}

// MARK: - Safe Array Indexing Helper

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
