import SwiftUI

/// List row displaying an individual `LibraryItem` in the user's library.
/// Shows cover art, titles, durations, track counts, and a circular progress ring.
public struct LibraryRow: View {
    public let item: LibraryItem
    public let isCurrentlyPlaying: Bool
    public var onPlay: (() -> Void)?
    public var onDelete: (() -> Void)?
    
    public init(
        item: LibraryItem,
        isCurrentlyPlaying: Bool = false,
        onPlay: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.onPlay = onPlay
        self.onDelete = onDelete
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Artwork Thumbnail with Playing Badge
            ZStack(alignment: .bottomTrailing) {
                ArtworkImageView(
                    artworkData: item.artworkData,
                    title: item.title,
                    kind: item.kind,
                    cornerRadius: 8
                )
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                
                if isCurrentlyPlaying {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .symbolEffect(.variableColor.iterative, isActive: isCurrentlyPlaying)
                        )
                        .offset(x: 3, y: 3)
                }
            }
            
            // Textual Information
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(isCurrentlyPlaying ? Color.accentColor : Color.primary)
                
                if let author = item.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    // Item Kind / Track Count Badge
                    if item.kind == .multiPart {
                        Label("\(item.playableTracks.count) parts", systemImage: "books.vertical")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    } else if item.kind == .folder {
                        Label("\(item.sortedChildren.count) items", systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                    
                    // Duration or Remaining Time
                    if item.totalDuration > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.6))
                        
                        Text(item.formattedTotalDuration)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    
                    // In-flight Watch Transfer indicator
                    if WatchSyncManager.shared.isTransferring(bookID: item.id) {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.6))
                        
                        HStack(spacing: 3) {
                            Image(systemName: "applewatch.radiowaves.left.and.right")
                                .font(.system(size: 9))
                            Text("\(Int(WatchSyncManager.shared.transferProgress(for: item.id) * 100))%")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            
            Spacer()
            
            // Right Accessor: Folder chevron OR Audio progress ring
            if item.kind == .folder {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            } else {
                VStack(spacing: 2) {
                    if item.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                    } else {
                        CircularProgressView(
                            progress: item.progress,
                            strokeWidth: 3,
                            ringColor: isCurrentlyPlaying ? .accentColor : .secondary
                        )
                        .frame(width: 26, height: 26)
                        
                        Text("\(Int(item.progress * 100))%")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if item.kind != .folder {
                Button {
                    onPlay?()
                } label: {
                    Label(isCurrentlyPlaying ? "Pause" : "Play", systemImage: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                }
                
                Button {
                    WatchSyncManager.shared.transferBookToWatch(item: item)
                } label: {
                    Label("Sync to Apple Watch", systemImage: "applewatch.side.right")
                }
                
                Button {
                    item.isCompleted.toggle()
                    item.lastUpdated = Date()
                } label: {
                    Label(
                        item.isCompleted ? "Mark as Unfinished" : "Mark as Finished",
                        systemImage: item.isCompleted ? "arrow.counterclockwise" : "checkmark"
                    )
                }
            }
            
            if let onDelete = onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
