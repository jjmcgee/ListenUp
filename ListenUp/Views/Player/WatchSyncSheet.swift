import SwiftUI
import SwiftData

/// Dedicated sheet presenting Apple Watch synchronization status,
/// active transfer progress, and one-tap offline sync triggers for the current audiobook.
public struct WatchSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchSyncManager.self) private var watchSync
    
    public let item: LibraryItem?
    
    public init(item: LibraryItem?) {
        self.item = item
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Watch Status Hero Card
                    watchStatusCard
                    
                    // Book Sync Action Section
                    if let item = item {
                        currentBookSyncCard(item)
                    }
                    
                    // Active Transfers Card
                    if !watchSync.activeTransfers.isEmpty {
                        activeTransfersSection
                    }
                    
                    // Informational Tip
                    offlineListeningTipCard
                }
                .padding(20)
            }
            .navigationTitle("Apple Watch Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Watch Status Hero Card
    
    private var watchStatusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(watchSync.isReachable ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 52, height: 52)
                
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(watchSync.isReachable ? Color.green : Color.orange)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(watchSync.isReachable ? "Apple Watch Connected" : "Apple Watch In Range")
                    .font(.headline)
                
                Text(
                    watchSync.isReachable
                        ? "Real-time remote control and sync active."
                        : "Background sync will resume automatically when watch wakes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Current Book Sync Card
    
    private func currentBookSyncCard(_ item: LibraryItem) -> some View {
        let isTransferring = watchSync.isTransferring(bookID: item.id)
        let progress = watchSync.transferProgress(for: item.id)
        let trackCount = item.playableTracks.count
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ArtworkImageView(
                    artworkData: item.artworkData,
                    title: item.title,
                    kind: item.kind,
                    cornerRadius: 8
                )
                .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let author = item.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text("\(trackCount) track\(trackCount == 1 ? "" : "s") • \(item.formattedTotalDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            if isTransferring {
                VStack(spacing: 8) {
                    HStack {
                        Text("Transferring to Apple Watch...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    watchSync.transferBookToWatch(item: item)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Sync to Apple Watch")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Active Transfers Section
    
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In-Flight Watch Transfers")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            ForEach(watchSync.activeTransfers) { transfer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transfer.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Text("Part \(transfer.partIndex + 1) of \(transfer.totalParts)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if transfer.isTransferring {
                        ProgressView(value: transfer.fractionCompleted)
                            .frame(width: 80)
                            .tint(Color.accentColor)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - Offline Listening Tip Card
    
    private var offlineListeningTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airpodspro")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Phone-Free Offline Listening")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(
                    "Once transferred, you can open ListenUp on your Apple Watch, connect your AirPods, and leave your iPhone behind. Your progress will automatically sync back when you return."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    WatchSyncSheet(
        item: LibraryItem(
            title: "Atomic Habits",
            author: "James Clear",
            kind: .singleFile,
            totalDuration: 18000.0
        )
    )
    .environment(WatchSyncManager.shared)
}
