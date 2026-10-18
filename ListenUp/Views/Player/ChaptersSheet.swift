import SwiftUI

/// Presentation sheet displaying the list of chapters and user bookmarks for the active audiobook.
public struct ChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    public enum SheetTab: String, CaseIterable, Identifiable {
        case chapters = "Chapters"
        case bookmarks = "Bookmarks"
        
        public var id: String { rawValue }
    }
    
    @State private var selectedTab: SheetTab = .chapters
    @State private var isShowingAddBookmarkAlert: Bool = false
    @State private var newBookmarkTitle: String = ""
    @State private var bookmarkToRename: UserBookmark? = nil
    @State private var renameBookmarkTitle: String = ""
    
    private var bookmarkStore = BookmarkStore.shared
    
    public init(player: AudioPlayerManager) {
        self.player = player
    }
    
    private var currentBookBookmarks: [UserBookmark] {
        guard let item = player.currentItem else { return [] }
        return bookmarkStore.bookmarks(for: item.id)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Tab Picker
                Picker("View", selection: $selectedTab) {
                    ForEach(SheetTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                
                switch selectedTab {
                case .chapters:
                    chaptersListView
                case .bookmarks:
                    bookmarksListView
                }
            }
            .navigationTitle(selectedTab.rawValue)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                if player.chapters.isEmpty && !player.isLoadingChapters {
                    player.reloadChapters()
                }
            }
            .onAppear {
                if player.chapters.isEmpty && !player.isLoadingChapters && !currentBookBookmarks.isEmpty {
                    selectedTab = .bookmarks
                }
            }
            .toolbar {
                // Leading circular 'X' dismiss button
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 34, height: 34)
                            .liquidGlassCircle(isInteractive: true)
                    }
                    .accessibilityLabel("Close")
                }
                
                // Trailing actions depending on active tab
                ToolbarItem(placement: .primaryAction) {
                    if selectedTab == .chapters {
                        Button {
                            player.reloadChapters()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Reload")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .liquidGlassCapsule(tint: Color.accentColor, isInteractive: true)
                        }
                        .disabled(player.isLoadingChapters)
                        .accessibilityLabel("Reload Chapters")
                    } else {
                        Button {
                            newBookmarkTitle = "Bookmark at \(TimeFormatting.formatTimestamp(player.currentTime))"
                            isShowingAddBookmarkAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.badge.plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .liquidGlassCapsule(tint: Color.accentColor, isInteractive: true)
                        }
                        .accessibilityLabel("Add Bookmark")
                    }
                }
            }
            .alert("Add Bookmark", isPresented: $isShowingAddBookmarkAlert) {
                TextField("Title", text: $newBookmarkTitle)
                Button("Save") {
                    if let book = player.currentItem {
                        bookmarkStore.addBookmark(
                            bookID: book.id,
                            title: newBookmarkTitle,
                            timestamp: player.currentTime
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save a bookmark at \(TimeFormatting.formatTimestamp(player.currentTime)).")
            }
            .alert(
                "Rename Bookmark",
                isPresented: Binding(
                    get: { bookmarkToRename != nil },
                    set: { if !$0 { bookmarkToRename = nil } }
                ),
                presenting: bookmarkToRename
            ) { bookmark in
                TextField("Title", text: $renameBookmarkTitle)
                Button("Save") {
                    bookmarkStore.updateBookmarkTitle(
                        bookmarkID: bookmark.id,
                        bookID: bookmark.bookID,
                        newTitle: renameBookmarkTitle
                    )
                    bookmarkToRename = nil
                }
                Button("Cancel", role: .cancel) {
                    bookmarkToRename = nil
                }
            }
        }
    }
    
    // MARK: - Chapters View
    
    @ViewBuilder
    private var chaptersListView: some View {
        if player.isLoadingChapters {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading chapters…")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if player.chapters.isEmpty {
            ContentUnavailableView {
                Label("No Chapters Found", systemImage: "book.pages")
            } description: {
                Text("This audiobook does not contain embedded chapter markers.")
            } actions: {
                Button {
                    player.reloadChapters()
                } label: {
                    Text("Try Reloading")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(player.chapters) { chapter in
                        Button {
                            player.skipToChapter(chapter)
                            dismiss()
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text("Start: \(TimeFormatting.formatChapterTimestamp(chapter.startTime)) - Duration: \(TimeFormatting.formatChapterDuration(chapter.duration))")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Spacer()
                                
                                if player.currentChapter?.id == chapter.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background {
                                if player.currentChapter?.id == chapter.id {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .id(chapter.id)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let currentId = player.currentChapter?.id {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(currentId, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Bookmarks View
    
    @ViewBuilder
    private var bookmarksListView: some View {
        let bookmarks = currentBookBookmarks
        if bookmarks.isEmpty {
            ContentUnavailableView {
                Label("No Bookmarks", systemImage: "bookmark")
            } description: {
                Text("Tap \"Add\" above to bookmark your current playback position.")
            }
        } else {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        player.seek(to: bookmark.timestamp)
                        dismiss()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                HStack(spacing: 6) {
                                    Text(TimeFormatting.formatTimestamp(bookmark.timestamp))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                    
                                    Text("•")
                                        .foregroundStyle(Color.secondary)
                                    
                                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .contextMenu {
                        Button {
                            renameBookmarkTitle = bookmark.title
                            bookmarkToRename = bookmark
                        } label: {
                            Label("Rename Bookmark", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            bookmarkStore.deleteBookmark(bookmarkID: bookmark.id, bookID: bookmark.bookID)
                        } label: {
                            Label("Delete Bookmark", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    if let bookID = player.currentItem?.id {
                        bookmarkStore.deleteBookmarks(for: bookID, at: offsets)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

#Preview("Chapters Sheet") {
    ChaptersSheet(player: .previewMock())
}
