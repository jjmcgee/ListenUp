import SwiftUI

/// WatchOS view for inspecting and managing downloaded audiobooks and local storage.
public struct WatchDownloadsView: View {
    @Environment(WatchLibraryStore.self) private var libraryStore
    
    public init() {}
    
    public var body: some View {
        List {
            // Storage Overview Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloaded Audio")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text(libraryStore.formattedStorageUsed())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Downloaded books can be played without your iPhone nearby.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Downloaded Books List
            let downloadedBooks = libraryStore.books.filter { libraryStore.downloadedBookIDs.contains($0.id) }
            
            if downloadedBooks.isEmpty {
                Section {
                    Text("No audiobooks downloaded yet. Tap any book in your Library to download it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                Section("Downloaded Books (\(downloadedBooks.count))") {
                    ForEach(downloadedBooks) { book in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                
                                let trackCount = libraryStore.localURLs(for: book.id).count
                                Text("\(trackCount) file\(trackCount == 1 ? "" : "s")")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                libraryStore.deleteDownloadedBook(bookID: book.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Storage")
    }
}

#Preview {
    NavigationStack {
        WatchDownloadsView()
            .environment(WatchLibraryStore.shared)
    }
}
