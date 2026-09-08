import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The root library screen displaying audiobooks and folders,
/// providing directory drilling, search, filtering, and `.fileImporter` ingestion.
public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerManager.self) private var player
    
    /// Optional parent folder for recursive drilling. When `nil`, shows root library.
    public let parentFolder: LibraryItem?
    
    @Query private var allItems: [LibraryItem]
    
    @State private var searchText: String = ""
    @State private var filterSelection: FilterOption = .all
    @State private var isShowingFileImporter: Bool = false
    @State private var isImporting: Bool = false
    @State private var importErrorMessage: String? = nil
    @State private var isShowingFullPlayer: Bool = false
    
    public enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In Progress"
        case completed = "Finished"
        
        public var id: String { rawValue }
    }
    
    public init(parentFolder: LibraryItem? = nil) {
        self.parentFolder = parentFolder
    }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if parentFolder == nil && !allItems.isEmpty {
                        Picker("Filter", selection: $filterSelection) {
                            ForEach(FilterOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
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
                                        LibraryView(parentFolder: item)
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
                                            player.play(item: item)
                                        },
                                        onDelete: {
                                            deleteItem(item)
                                        }
                                    )
                                    .onTapGesture {
                                        player.play(item: item)
                                    }
                                }
                            }
                            .onDelete(perform: deleteItems)
                            
                            // Extra spacer padding at bottom to prevent floating mini-player from occluding items
                            if player.currentItem != nil {
                                Color.clear
                                    .frame(height: 70)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                
                // Floating Mini-Player Dock
                if player.currentItem != nil {
                    MiniPlayerView(player: player) {
                        isShowingFullPlayer = true
                    }
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(parentFolder?.title ?? "ListenUp")
            .searchable(text: $searchText, prompt: "Search audiobooks & courses...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import", systemImage: "plus.circle.fill")
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
            .sheet(isPresented: $isShowingFullPlayer) {
                FullPlayerView(player: player)
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
        }
    }
    
    // MARK: - Filtered Items
    
    private var displayedItems: [LibraryItem] {
        let baseItems: [LibraryItem]
        if let parent = parentFolder {
            baseItems = parent.sortedChildren
        } else {
            // Root items only (parent == nil)
            baseItems = allItems.filter { $0.parent == nil }
        }
        
        return baseItems.filter { item in
            // Search filter
            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                (item.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            
            guard matchesSearch else { return false }
            
            // Tab filter
            switch filterSelection {
            case .all:
                return true
            case .inProgress:
                return !item.isCompleted && item.currentPosition > 0
            case .completed:
                return item.isCompleted
            }
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
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(Color.secondary.opacity(0.4))
            
            Text(parentFolder == nil ? "Your Library is Empty" : "Folder is Empty")
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
    
    // MARK: - Deletion
    
    private func deleteItem(_ item: LibraryItem) {
        if player.currentItem?.id == item.id || item.playableTracks.contains(where: { $0.id == player.currentItem?.id }) {
            player.stop()
        }
        FileImporterService.deletePhysicalFiles(for: item)
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = displayedItems[index]
            deleteItem(item)
        }
    }
}
