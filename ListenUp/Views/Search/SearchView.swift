import SwiftUI
import SwiftData

/// Dedicated search screen displaying "Recent" items or live filtered search results.
public struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerManager.self) private var player
    
    public let searchText: String
    
    @Query(sort: \LibraryItem.lastUpdated, order: .reverse)
    private var allItems: [LibraryItem]
    
    public init(searchText: String = "") {
        self.searchText = searchText
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Section Header
                    Text(headerTitle)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    if displayedItems.isEmpty {
                        emptyStateView
                    } else {
                        // Grouped card matching the screenshot layout
                        VStack(spacing: 0) {
                            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                                searchRow(for: item)
                                
                                if index < displayedItems.count - 1 {
                                    Divider()
                                        .padding(.leading, 78)
                                        .opacity(0.4)
                                }
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                #if canImport(UIKit)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                #else
                                .fill(Color.secondary.opacity(0.12))
                                #endif
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Bottom spacer allowing content to scroll clear of the floating search bar & keyboard
                    Color.clear
                        .frame(height: 140)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            #if canImport(UIKit)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            #else
            .background(Color.secondary.opacity(0.06).ignoresSafeArea())
            #endif
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }
    
    // MARK: - Row Subview
    
    @ViewBuilder
    private func searchRow(for item: LibraryItem) -> some View {
        let isPlaying = isItemPlaying(item)
        
        Button {
            player.play(item: item)
        } label: {
            HStack(spacing: 14) {
                // Artwork Thumbnail
                ArtworkImageView(
                    artworkData: item.artworkData,
                    title: item.title,
                    kind: item.kind,
                    cornerRadius: 8
                )
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                
                // Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    
                    Text(subtitleText(for: item))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                    
                    Text(durationText(for: item))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
                
                Spacer()
                
                // Progress Indicator
                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                } else {
                    CircularProgressView(
                        progress: item.progress,
                        strokeWidth: 2.5,
                        ringColor: isPlaying ? .accentColor : .secondary.opacity(0.6)
                    )
                    .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Filtered Data
    
    private var headerTitle: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Recent" : "Results"
    }
    
    private var displayedItems: [LibraryItem] {
        let rootItems = allItems.filter { $0.parent == nil }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return rootItems
        }
        
        return rootItems.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed) ||
            (item.author?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
    
    private func subtitleText(for item: LibraryItem) -> String {
        if let author = item.author, !author.isEmpty {
            return author
        }
        if item.kind == .multiPart {
            return "\(item.playableTracks.count) Files"
        }
        if item.kind == .folder {
            return "\(item.sortedChildren.count) Items"
        }
        return "Audiobook"
    }
    
    private func durationText(for item: LibraryItem) -> String {
        if item.totalDuration > 0 {
            return TimeFormatting.formatTimestamp(item.totalDuration)
        }
        return ""
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
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .padding(.top, 40)
            
            Text("No Results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(Color.secondary)
            
            Text("Check spelling or try a different term.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

#Preview {
    SearchView(searchText: "")
        .environment(AudioPlayerManager())
        .modelContainer(for: LibraryItem.self, inMemory: true)
}
