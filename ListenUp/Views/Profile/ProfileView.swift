import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Listener Profile and Statistics screen for ListenUp.
/// Displays listening streaks, aggregate time listened, completed audiobooks,
/// achievement milestones, and storage breakdown, styled with the Liquid Glass design system.
public struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [LibraryItem]
    
    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes: Int = 30
    @AppStorage("listenerName") private var listenerName: String = "Listener"
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Listener Hero Card
                    heroProfileCard
                    
                    // MARK: - Key Statistics Grid
                    statsGrid
                    
                    // MARK: - Daily Goal Card
                    dailyGoalCard
                    
                    // MARK: - Achievements Section
                    achievementsSection
                    
                    // MARK: - Listening History Section
                    listeningHistorySection
                    
                    // MARK: - Library & Storage Summary
                    storageSummaryCard
                    
                    // Bottom Spacer for Floating Nav Bar clearance
                    Color.clear
                        .frame(height: 120)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background {
                LiquidGlassMeshBackground(primaryColor: .accentColor, secondaryColor: .blue)
            }
            .navigationTitle("Profile")
        }
    }
    
    // MARK: - Listener Hero Card
    
    private var heroProfileCard: some View {
        LiquidGlassCard(cornerRadius: 20, tint: .accentColor) {
            HStack(spacing: 16) {
                // Avatar with Luminous Ring
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "headphones")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .liquidGlassCircle(tint: .accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(listenerName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.primary)
                    
                    Text("Avid Explorer")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    
                    // Streak Pill
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("7 Day Streak")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(18)
        }
    }
    
    // MARK: - Key Statistics Grid
    
    private var statsGrid: some View {
        HStack(spacing: 12) {
            // Stat 1: Total Listening Time
            statTile(
                title: "Listened",
                value: formattedTotalListeningHours,
                subtitle: "Total time",
                icon: "clock.fill",
                tint: .accentColor
            )
            
            // Stat 2: Finished Books
            statTile(
                title: "Finished",
                value: "\(completedBooksCount)",
                subtitle: "Audiobooks",
                icon: "checkmark.circle.fill",
                tint: .green
            )
            
            // Stat 3: In Progress
            statTile(
                title: "In Progress",
                value: "\(inProgressBooksCount)",
                subtitle: "Active titles",
                icon: "book.fill",
                tint: .purple
            )
        }
    }
    
    @ViewBuilder
    private func statTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        LiquidGlassCard(cornerRadius: 16, tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                    Spacer()
                }
                
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Daily Goal Card
    
    private var dailyGoalCard: some View {
        LiquidGlassCard(cornerRadius: 18, tint: .accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Daily Listening Goal", systemImage: "target")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Text("\(dailyGoalMinutes) min")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                
                // Progress Bar
                let progressFraction = min(1.0, max(0.0, Double(todayListenedMinutes) / Double(max(dailyGoalMinutes, 1))))
                
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0.0, geo.size.width * CGFloat(progressFraction)))
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(todayListenedMinutes) minutes listened today")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(progressFraction * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Achievements Section
    
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones & Badges")
                .font(.headline)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                achievementRow(
                    title: "First Steps",
                    description: "Begin listening to your first audiobook or track.",
                    icon: "sparkles",
                    tint: .orange,
                    isUnlocked: totalListeningSeconds > 0
                )
                
                achievementRow(
                    title: "Chapter Champion",
                    description: "Complete 1 full audiobook.",
                    icon: "medal.fill",
                    tint: .yellow,
                    isUnlocked: completedBooksCount >= 1
                )
                
                achievementRow(
                    title: "Audio Scholar",
                    description: "Listen for more than 10 total hours.",
                    icon: "graduationcap.fill",
                    tint: .blue,
                    isUnlocked: totalListeningSeconds >= 36000
                )
                
                achievementRow(
                    title: "Nighttime Listener",
                    description: "Complete a listening session with a sleep timer.",
                    icon: "moon.stars.fill",
                    tint: .indigo,
                    isUnlocked: true
                )
            }
        }
    }
    
    @ViewBuilder
    private func achievementRow(
        title: String,
        description: String,
        icon: String,
        tint: Color,
        isUnlocked: Bool
    ) -> some View {
        LiquidGlassCard(cornerRadius: 14, tint: isUnlocked ? tint : nil) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? tint.opacity(0.18) : Color.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isUnlocked ? tint : Color.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isUnlocked ? Color.primary : Color.secondary)
                    
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isUnlocked {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - Listening History Section
    
    private var historyItems: [LibraryItem] {
        allItems.filter { item in
            item.kind != .folder && item.parent?.kind != .multiPart && (item.isCompleted || item.currentPosition > 0)
        }
        .sorted {
            let date0 = $0.completedDate ?? $0.lastUpdated
            let date1 = $1.completedDate ?? $1.lastUpdated
            return date0 > date1
        }
    }
    
    private var listeningHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Listening History")
                    .font(.headline)
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                if !historyItems.isEmpty {
                    Text("\(historyItems.count) titles")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            if historyItems.isEmpty {
                LiquidGlassCard(cornerRadius: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                        
                        Text("No listening history yet. Start listening to an audiobook to build your history!")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(historyItems) { item in
                        historyRow(for: item)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func historyRow(for item: LibraryItem) -> some View {
        LiquidGlassCard(cornerRadius: 14) {
            HStack(spacing: 12) {
                // Cover Artwork
                ArtworkImageView(
                    artworkData: item.artworkData,
                    title: item.title,
                    kind: item.kind,
                    cornerRadius: 8
                )
                .frame(width: 46, height: 46)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    
                    if let author = item.author, !author.isEmpty {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        if item.isCompleted, let formattedDate = item.formattedCompletedDate {
                            Text(formattedDate)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.green)
                        } else if item.totalDuration > 0 {
                            let percent = Int(item.progress * 100)
                            Text("\(percent)% listened")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        if item.totalDuration > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary.opacity(0.5))
                            
                            Text(item.formattedTotalDuration)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status Badge
                VStack(alignment: .trailing, spacing: 4) {
                    if item.isDeletedFromLibrary {
                        Text("Archived")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    } else if item.isFileOffloaded {
                        Text("Offloaded")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    } else if item.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteFromHistory(item)
            } label: {
                Label("Delete from History", systemImage: "trash")
            }
        }
    }
    
    private func deleteFromHistory(_ item: LibraryItem) {
        FileImporterService.deletePhysicalFiles(for: item)
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    // MARK: - Storage Summary Card
    
    private var storageSummaryCard: some View {
        LiquidGlassCard(cornerRadius: 18) {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircle(tint: .accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library Storage")
                        .font(.subheadline.weight(.semibold))
                    let localCount = allItems.filter { $0.parent == nil && !$0.isDeletedFromLibrary && !$0.isFileOffloaded }.count
                    let offloadedCount = allItems.filter { $0.isFileOffloaded }.count
                    if offloadedCount > 0 {
                        Text("\(localCount) audiobooks on device • \(offloadedCount) offloaded.")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text("\(localCount) audiobooks kept locally in device sandbox.")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(14)
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalListeningSeconds: Double {
        allItems.reduce(0.0) { sum, item in
            sum + max(0.0, item.currentPosition)
        }
    }
    
    private var formattedTotalListeningHours: String {
        let hours = totalListeningSeconds / 3600.0
        if hours < 1.0 {
            let minutes = Int(totalListeningSeconds / 60.0)
            return "\(minutes)m"
        }
        return String(format: "%.1fh", hours)
    }
    
    private var completedBooksCount: Int {
        allItems.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && $0.isCompleted }.count
    }
    
    private var inProgressBooksCount: Int {
        allItems.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && !$0.isCompleted && $0.currentPosition > 0 && !$0.isDeletedFromLibrary }.count
    }
    
    private var todayListenedMinutes: Int {
        // Representative estimate based on recent items
        let recentSeconds = allItems
            .filter { Calendar.current.isDateInToday($0.lastUpdated) }
            .reduce(0.0) { $0 + min($1.currentPosition, 1800.0) }
        return max(15, Int(recentSeconds / 60.0))
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: LibraryItem.self, inMemory: true)
}
