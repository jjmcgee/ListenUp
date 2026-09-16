import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Dedicated sheet presenting Apple Watch synchronization status,
/// active transfer progress, and one-tap offline sync triggers for the current audiobook.
/// Styled with luminous Liquid Glass cards and specular rim lighting.
public struct WatchSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchSyncManager.self) private var envWatchSync: WatchSyncManager?
    
    private var watchSync: WatchSyncManager {
        envWatchSync ?? .shared
    }
    
    public let item: LibraryItem?
    
    public init(item: LibraryItem?) {
        self.item = item
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassMeshBackground(
                    primaryColor: watchSync.isReachable ? .green : .orange,
                    secondaryColor: .accentColor
                )
                
                ScrollView {
                    VStack(spacing: 18) {
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
            }
            .navigationTitle("Apple Watch Sync")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    doneButton
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    doneButton
                }
                #endif
            }
        }
    }
    
    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
        .fontWeight(.semibold)
    }
    
    // MARK: - Watch Status Hero Card
    
    private var watchStatusCard: some View {
        LiquidGlassCard(cornerRadius: 18, tint: watchSync.isReachable ? .green : .orange) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(watchSync.isReachable ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(watchSync.isReachable ? Color.green : Color.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(watchSync.isReachable ? "Apple Watch Connected" : "Apple Watch In Range")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    
                    Text(
                        watchSync.isReachable
                            ? "Real-time remote control and sync active."
                            : "Background sync will resume automatically when watch wakes."
                    )
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    // MARK: - Current Book Sync Card
    
    private func currentBookSyncCard(_ item: LibraryItem) -> some View {
        let isTransferring = watchSync.isTransferring(bookID: item.id)
        let progress = watchSync.transferProgress(for: item.id)
        let trackCount = item.playableTracks.count
        
        return LiquidGlassCard(cornerRadius: 18, tint: .accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ArtworkImageView(
                        artworkData: item.artworkData,
                        title: item.title,
                        kind: item.kind,
                        cornerRadius: 8
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(Color.primary)
                        
                        if let author = item.author, !author.isEmpty {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        
                        Text("\(trackCount) track\(trackCount == 1 ? "" : "s") • \(item.formattedTotalDuration)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                
                Divider()
                    .opacity(0.5)
                
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
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        watchSync.transferBookToWatch(item: item)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Sync to Apple Watch")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Active Transfers Section
    
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In-Flight Watch Transfers")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.secondary)
            
            ForEach(watchSync.activeTransfers) { transfer in
                LiquidGlassCard(cornerRadius: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transfer.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            
                            Text("Part \(transfer.partIndex + 1) of \(transfer.totalParts)")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
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
                }
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
                .foregroundStyle(Color.secondary)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14, tint: .accentColor)
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
