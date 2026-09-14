import SwiftUI

/// Detail sheet for an individual audiobook on Apple Watch.
/// Allows triggering local watch playback, phone remote playback, initiating download, or removing files.
public struct WatchBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLibraryStore.self) private var libraryStore
    @Environment(WatchSyncManager.self) private var syncManager
    @Environment(WatchAudioPlayerManager.self) private var localPlayer
    
    public let book: WatchLibraryItemSummary
    public var onPlayTriggered: (() -> Void)?
    
    public init(book: WatchLibraryItemSummary, onPlayTriggered: (() -> Void)? = nil) {
        self.book = book
        self.onPlayTriggered = onPlayTriggered
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Titles
                VStack(spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 15, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                    
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Metadata Badges
                HStack(spacing: 8) {
                    if book.totalDuration > 0 {
                        Text(TimeFormatting.formatVerbalDuration(book.totalDuration))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    if book.trackCount > 1 {
                        Text("\(book.trackCount) tracks")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Divider()
                
                // Actions based on Download Status
                let status = libraryStore.status(for: book.id)
                
                switch status {
                case .downloaded:
                    VStack(spacing: 6) {
                        // Play on Watch
                        Button {
                            let urls = libraryStore.localURLs(for: book.id)
                            localPlayer.play(
                                bookID: book.id,
                                title: book.title,
                                author: book.author,
                                urls: urls,
                                startPosition: book.currentPosition
                            )
                            dismiss()
                            onPlayTriggered?()
                        } label: {
                            Label("Play on Watch", systemImage: "applewatch.side.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.green)
                        
                        // Play on iPhone
                        Button {
                            syncManager.sendRemoteCommand(WatchRemoteCommand(type: .play, value: nil))
                            dismiss()
                            onPlayTriggered?()
                        } label: {
                            Label("Play on iPhone", systemImage: "iphone")
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        // Remove Download
                        Button(role: .destructive) {
                            libraryStore.deleteDownloadedBook(bookID: book.id)
                        } label: {
                            Label("Delete Download", systemImage: "trash")
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    
                case .downloading(let progress):
                    VStack(spacing: 6) {
                        Text("Downloading to Watch...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                            .padding(.horizontal, 8)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        // Can still play on iPhone while downloading
                        Button {
                            syncManager.sendRemoteCommand(WatchRemoteCommand(type: .play, value: nil))
                            dismiss()
                            onPlayTriggered?()
                        } label: {
                            Label("Play on iPhone", systemImage: "iphone")
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                case .onPhoneOnly:
                    VStack(spacing: 6) {
                        // Download to Watch
                        Button {
                            libraryStore.requestDownload(for: book.id)
                        } label: {
                            Label("Download to Watch", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        
                        // Play on iPhone
                        Button {
                            syncManager.sendRemoteCommand(WatchRemoteCommand(type: .play, value: nil))
                            dismiss()
                            onPlayTriggered?()
                        } label: {
                            Label("Play on iPhone", systemImage: "iphone")
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .navigationTitle("Audiobook")
    }
}

#Preview {
    NavigationStack {
        WatchBookDetailView(
            book: WatchLibraryItemSummary(
                id: UUID(),
                title: "Atomic Habits",
                author: "James Clear",
                kindRaw: "singleFile",
                totalDuration: 19800,
                currentPosition: 3600,
                isCompleted: false,
                lastUpdated: Date(),
                trackCount: 1
            )
        )
        .environment(WatchLibraryStore.shared)
        .environment(WatchSyncManager.shared)
        .environment(WatchAudioPlayerManager.shared)
    }
}
