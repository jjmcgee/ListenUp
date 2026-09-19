import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// The root library screen displaying audiobooks and folders,
/// providing directory drilling, search filtering, and `.fileImporter` ingestion.
public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerManager.self) private var player
    
    /// Optional parent folder for recursive drilling. When `nil`, shows root library.
    public let parentFolder: LibraryItem?
    
    /// Search query passed from the bottom floating navigation bar or internal state.
    public let searchText: String
    
    @Query private var allItems: [LibraryItem]
    
    @State private var filterSelection: FilterOption = .all
    @State private var isShowingFileImporter: Bool = false
    @State private var isImporting: Bool = false
    @State private var importErrorMessage: String? = nil
    @State private var bookPendingDeletionPrompt: LibraryItem? = nil
    @State private var itemShowingOffloadedAlert: LibraryItem? = nil
    
    public enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In Progress"
        case completed = "Finished"
        
        public var id: String { rawValue }
    }
    
    public init(parentFolder: LibraryItem? = nil, searchText: String = "") {
        self.parentFolder = parentFolder
        self.searchText = searchText
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if parentFolder == nil && !allItems.filter({ !$0.isDeletedFromLibrary }).isEmpty {
                    HStack(spacing: 6) {
                        ForEach(FilterOption.allCases) { option in
                            let isSelected = filterSelection == option
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    filterSelection = option
                                }
                            } label: {
                                Text(option.rawValue)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        if isSelected {
                                            Capsule()
                                                .fill(Color.accentColor.opacity(0.15))
                                                .overlay {
                                                    Capsule()
                                                        .strokeBorder(
                                                            LinearGradient(
                                                                colors: [Color.white.opacity(0.4), Color.clear],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1
                                                        )
                                                }
                                                .shadow(color: Color.accentColor.opacity(0.18), radius: 4, x: 0, y: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .liquidGlassCapsule(tint: Color.accentColor)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // Main Library List or Empty State
                if displayedItems.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(displayedItems) { item in
                            if item.kind == .folder {
                                NavigationLink {
                                    LibraryView(parentFolder: item, searchText: searchText)
                                } label: {
                                    LibraryRow(
                                        item: item,
                                        isCurrentlyPlaying: isItemPlaying(item),
                                        onDelete: {
                                            deleteItem(item)
                                        }
                                    )
                                }
                            } else {
                                LibraryRow(
                                    item: item,
                                    isCurrentlyPlaying: isItemPlaying(item),
                                    onPlay: {
                                        if item.isFileOffloaded {
                                            itemShowingOffloadedAlert = item
                                        } else {
                                            player.play(item: item)
                                        }
                                    },
                                    onDelete: {
                                        deleteItem(item)
                                    },
                                    onToggleCompleted: {
                                        toggleCompleted(for: item)
                                    },
                                    onDeleteAudioFile: {
                                        offloadFile(for: item)
                                    }
                                )
                                .onTapGesture {
                                    if item.isFileOffloaded {
                                        itemShowingOffloadedAlert = item
                                    } else {
                                        player.play(item: item)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteItems)
                        
                        // Extra bottom padding to ensure items scroll clear of the floating bottom bar & mini player
                        Color.clear
                            .frame(height: 120)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(parentFolder?.title ?? "Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "book.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlassCapsule(tint: Color.accentColor, isInteractive: true)
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.audio, .folder],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("Importing Audio...")
                            .padding(20)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .alert("Import Error", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert(
                "Delete Audio File?",
                isPresented: Binding(
                    get: { bookPendingDeletionPrompt != nil },
                    set: { if !$0 { bookPendingDeletionPrompt = nil } }
                ),
                presenting: bookPendingDeletionPrompt
            ) { item in
                Button("Delete File", role: .destructive) {
                    offloadFile(for: item)
                    bookPendingDeletionPrompt = nil
                }
                Button("Keep File", role: .cancel) {
                    bookPendingDeletionPrompt = nil
                }
            } message: { item in
                Text("You marked \"\(item.title)\" as finished. Would you like to delete the audio file to free up storage? Your listening history will be preserved.")
            }
            .alert(
                "Audio File Offloaded",
                isPresented: Binding(
                    get: { itemShowingOffloadedAlert != nil },
                    set: { if !$0 { itemShowingOffloadedAlert = nil } }
                ),
                presenting: itemShowingOffloadedAlert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { item in
                Text("The audio file for \"\(item.title)\" was removed to save storage. Your completion status and listening history are preserved.")
            }
        }
    }
    
    // MARK: - Filtered Items
    
    private var displayedItems: [LibraryItem] {
        let baseItems: [LibraryItem]
        if let parent = parentFolder {
            baseItems = parent.sortedChildren.filter { !$0.isDeletedFromLibrary }
        } else {
            switch filterSelection {
            case .all:
                // Root items only (parent == nil and active in library)
                baseItems = allItems.filter { $0.parent == nil && !$0.isDeletedFromLibrary }
            case .inProgress:
                // All active audiobooks (excluding structural folders, child tracks, and soft-deleted items)
                baseItems = allItems.filter { item in
                    item.kind != .folder && item.parent?.kind != .multiPart && !item.isCompleted && item.currentPosition > 0 && !item.isDeletedFromLibrary
                }
            case .completed:
                // All finished audiobooks in library (excluding structural folders, child tracks, and soft-deleted items)
                baseItems = allItems.filter { item in
                    item.kind != .folder && item.parent?.kind != .multiPart && item.isCompleted && !item.isDeletedFromLibrary
                }
            }
        }
        
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return baseItems.filter { item in
            // Search filter
            let matchesSearch = trimmedQuery.isEmpty ||
                item.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                (item.author?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
            
            guard matchesSearch else { return false }
            
            // Tab filter when drilled into a parent folder
            if parentFolder != nil {
                guard !item.isDeletedFromLibrary else { return false }
                switch filterSelection {
                case .all:
                    return true
                case .inProgress:
                    return item.kind != .folder && !item.isCompleted && item.currentPosition > 0
                case .completed:
                    return item.kind != .folder && item.isCompleted
                }
            }
            
            return true
        }
    }
    
    private func isItemPlaying(_ item: LibraryItem) -> Bool {
        guard let current = player.currentItem else { return false }
        if current.id == item.id { return true }
        if item.kind == .folder {
            return item.playableTracks.contains { $0.id == current.id }
        }
        return false
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                
                Text("No Results Found")
                    .font(.title3.weight(.bold))
                
                Text("No audiobooks matching \"\(searchText)\" were found in your library.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                switch filterSelection {
                case .completed:
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    
                    Text("No Finished Books")
                        .font(.title3.weight(.bold))
                    
                    Text("Keep reading and finished items will appear.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                case .inProgress:
                    Image(systemName: "clock")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    
                    Text("No Books In Progress")
                        .font(.title3.weight(.bold))
                    
                    Text("Start listening to an audiobook and it will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                case .all:
                    if parentFolder == nil {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                        
                        Text("Your Library is Empty")
                            .font(.title3.weight(.bold))
                        
                        Text("Import single audiobooks (.m4b, .m4a, .mp3) or entire multi-track course folders.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("Import Audio Files", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 8)
                    } else {
                        Image(systemName: "folder")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                        
                        Text("Folder is Empty")
                            .font(.title3.weight(.bold))
                        
                        Text("This folder contains no audio tracks.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - File Import Handler
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            isImporting = true
            
            Task {
                do {
                    let dto = try await FileImporterService.shared.processImport(from: selectedURL)
                    await MainActor.run {
                        _ = FileImporterService.persist(
                            dto: dto,
                            into: modelContext,
                            parent: parentFolder
                        )
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        importErrorMessage = error.localizedDescription
                    }
                }
            }
            
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Completion & Offloading Actions
    
    private func toggleCompleted(for item: LibraryItem) {
        if item.isCompleted {
            item.isCompleted = false
            item.completedDate = nil
            item.lastUpdated = Date()
            try? modelContext.save()
        } else {
            item.isCompleted = true
            item.completedDate = Date()
            item.lastUpdated = Date()
            try? modelContext.save()
            
            if !item.isFileOffloaded {
                bookPendingDeletionPrompt = item
            }
        }
    }
    
    private func offloadFile(for item: LibraryItem) {
        if player.currentItem?.id == item.id || item.playableTracks.contains(where: { $0.id == player.currentItem?.id }) {
            player.stop()
        }
        FileImporterService.deletePhysicalFiles(for: item)
        item.isFileOffloaded = true
        item.lastUpdated = Date()
        try? modelContext.save()
    }
    
    // MARK: - Deletion
    
    private func deleteItem(_ item: LibraryItem) {
        if player.currentItem?.id == item.id || item.playableTracks.contains(where: { $0.id == player.currentItem?.id }) {
            player.stop()
        }
        FileImporterService.deletePhysicalFiles(for: item)
        
        // If the book has listening history or completion, preserve it for profile stats and history
        if item.isCompleted || item.currentPosition > 0 {
            item.isDeletedFromLibrary = true
            item.isFileOffloaded = true
            item.parent = nil
            item.lastUpdated = Date()
            try? modelContext.save()
        } else {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = displayedItems[index]
            deleteItem(item)
        }
    }
    
    // MARK: - Toolbar Item Label
    
    @ViewBuilder
    private var addBookLabel: some View {
        #if canImport(UIKit)
        if UIImage(systemName: "book.badge.plus") != nil {
            Label("Add Book", systemImage: "book.badge.plus")
        } else {
            Label {
                Text("Add Book")
            } icon: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 19))
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                        .offset(x: 5, y: 4)
                }
            }
        }
        #else
        Label("Add Book", systemImage: "book.badge.plus")
        #endif
    }
}

#Preview {
    LibraryView()
        .environment(AudioPlayerManager())
        .modelContainer(for: LibraryItem.self, inMemory: true)
}

