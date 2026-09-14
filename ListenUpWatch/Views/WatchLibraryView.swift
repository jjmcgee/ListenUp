import SwiftUI

/// WatchOS view displaying the catalog of audiobooks available on the iPhone and downloaded locally.
public struct WatchLibraryView: View {
    @Environment(WatchLibraryStore.self) private var libraryStore
    @Environment(WatchSyncManager.self) private var syncManager
    
    public var onSelectBookToPlay: (() -> Void)?
    
    public init(onSelectBookToPlay: (() -> Void)? = nil) {
        self.onSelectBookToPlay = onSelectBookToPlay
    }
    
    public var body: some View {
        List {
            if libraryStore.books.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    
                    Text("No Books Found")
                        .font(.headline)
                    
                    Text("Sync books from your iPhone or tap refresh.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        syncManager.requestLibraryCatalog()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(libraryStore.books) { book in
                    NavigationLink {
                        WatchBookDetailView(book: book, onPlayTriggered: onSelectBookToPlay)
                    } label: {
                        watchBookRow(book)
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    syncManager.requestLibraryCatalog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
    
    @ViewBuilder
    private func watchBookRow(_ book: WatchLibraryItemSummary) -> some View {
        let status = libraryStore.status(for: book.id)
        
        HStack(spacing: 8) {
            // Status Icon Indicator
            ZStack {
                switch status {
                case .downloaded:
                    Image(systemName: "applewatch.side.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                case .downloading(let prog):
                    ProgressView(value: prog)
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                case .onPhoneOnly:
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 22, height: 22)
            
            // Textual Details
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    if book.totalDuration > 0 {
                        Text(TimeFormatting.formatVerbalDuration(book.totalDuration))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    
                    if book.isCompleted {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("Finished")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    } else if book.currentPosition > 0 && book.totalDuration > 0 {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        let percent = Int((book.currentPosition / book.totalDuration) * 100)
                        Text("\(percent)%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        WatchLibraryView()
            .environment(WatchLibraryStore.shared)
            .environment(WatchSyncManager.shared)
    }
}
