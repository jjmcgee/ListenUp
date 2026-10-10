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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allItems: [LibraryItem]
    
    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes: Int = 30
    
    private enum ListeningStatsTab: String, CaseIterable, Identifiable {
        case today = "Today"
        case monthly = "Monthly"
        case total = "Total"
        
        var id: String { rawValue }
        var title: String { rawValue }
    }
    
    @State private var selectedStatsTab: ListeningStatsTab = .today
    @State private var isShowingGoalEditor: Bool = false
    @State private var statsStore = ListeningStatsStore.shared
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Listening Stats Section
                    listeningStatsSection
                    
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
            .onAppear {
                statsStore.handleDayChanged()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    statsStore.handleDayChanged()
                }
            }
            .sheet(isPresented: $isShowingGoalEditor) {
                DailyGoalEditorSheet(goalMinutes: $dailyGoalMinutes)
            }
        }
    }
    
    // MARK: - Listening Stats Section
    
    private var listeningStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listening Stats")
                .font(.headline)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 4)
            
            LiquidGlassCard(cornerRadius: 20, tint: .accentColor) {
                VStack(spacing: 16) {
                    // Segmented Tab Picker: [ Today | Monthly | Total ]
                    listeningStatsPicker
                    
                    // Tab Content
                    Group {
                        switch selectedStatsTab {
                        case .today:
                            todayStatsView
                        case .monthly:
                            monthlyStatsView
                        case .total:
                            totalStatsView
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .padding(18)
            }
        }
    }
    
    private var listeningStatsPicker: some View {
        HStack(spacing: 4) {
            ForEach(ListeningStatsTab.allCases) { tab in
                let isSelected = selectedStatsTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                        selectedStatsTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                                    }
                                    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
    
    // MARK: - Today Stats View
    
    private var todayStatsView: some View {
        let (hours, mins) = statsStore.todayHoursAndMinutes(from: allItems)
        let goalProgress = statsStore.dailyGoalProgress(goalMinutes: dailyGoalMinutes, from: allItems)
        let totalMinutes = goalProgress.listenedMinutes
        let progress = goalProgress.fraction
        
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if hours > 0 {
                    Text("\(hours)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("hrs")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.secondary)
                    
                    Text("\(mins)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .padding(.leading, 8)
                    Text("mins")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.secondary)
                } else {
                    Text("\(mins)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("mins")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
                
                // Mini Goal Percentage Chip
                Button {
                    isShowingGoalEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: goalProgress.isAccomplished ? "checkmark.circle.fill" : "target")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(goalProgress.isAccomplished ? Color.green : Color.accentColor)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(goalProgress.isAccomplished ? Color.green : Color.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((goalProgress.isAccomplished ? Color.green : Color.accentColor).opacity(0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Goal progress indicator
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: goalProgress.isAccomplished ? [Color.green, Color.mint] : [Color.accentColor, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0.0, geo.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text(goalProgress.isAccomplished ? "Daily goal accomplished!" : "\(totalMinutes) of \(dailyGoalMinutes) min daily goal")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    
                    Spacer()
                    
                    if !goalProgress.isAccomplished {
                        Text("\(goalProgress.remainingMinutes) min left")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Monthly Stats Chart View
    
    private var monthlyStatsView: some View {
        let comparison = statsStore.monthlyComparison(from: allItems)
        let prevHours = comparison.previousMonthHours
        let currHours = comparison.currentMonthHours
        let maxHours = max(prevHours, currHours, 2.0)
        
        return VStack(spacing: 16) {
            // Chart Area with Y-axis scale and grid lines
            HStack(alignment: .bottom, spacing: 12) {
                // Y-Axis Scale
                VStack(alignment: .trailing) {
                    Text(String(format: "%.0fh", maxHours))
                    Spacer()
                    Text(String(format: "%.0fh", maxHours / 2.0))
                    Spacer()
                    Text("0h")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
                .frame(width: 28, height: 110)
                
                // Chart Plot Area
                ZStack(alignment: .bottom) {
                    // Grid lines
                    VStack {
                        Divider().background(Color.secondary.opacity(0.15))
                        Spacer()
                        Divider().background(Color.secondary.opacity(0.15))
                        Spacer()
                        Divider().background(Color.secondary.opacity(0.25))
                    }
                    .frame(height: 110)
                    
                    // The Two Bars: Previous Month and Current Month
                    HStack(spacing: 40) {
                        monthBarColumn(
                            monthName: comparison.previousMonthName,
                            hours: prevHours,
                            maxHours: maxHours,
                            isCurrentMonth: false
                        )
                        
                        monthBarColumn(
                            monthName: comparison.currentMonthName,
                            hours: currHours,
                            maxHours: maxHours,
                            isCurrentMonth: true
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 110)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            
            // Trend / Comparison Pill
            monthlyComparisonPill(comparison: comparison)
        }
        .padding(.vertical, 4)
    }
    
    private func monthBarColumn(
        monthName: String,
        hours: Double,
        maxHours: Double,
        isCurrentMonth: Bool
    ) -> some View {
        let safeMax = max(maxHours, 0.1)
        let barHeightRatio = min(1.0, max(0.0, hours / safeMax))
        let barHeight = max(8.0, CGFloat(barHeightRatio) * 85.0)
        
        return VStack(spacing: 6) {
            // Value above bar
            Text(String(format: "%.1fh", hours))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrentMonth ? Color.accentColor : Color.secondary)
            
            // Bar
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isCurrentMonth ?
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .top,
                        endPoint: .bottom
                    ) :
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.55), Color.secondary.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 48, height: barHeight)
                .shadow(
                    color: isCurrentMonth ? Color.accentColor.opacity(0.3) : Color.clear,
                    radius: 6,
                    y: 2
                )
            
            // X-Axis Month Label
            Text(monthName)
                .font(.system(size: 13, weight: isCurrentMonth ? .bold : .medium))
                .foregroundStyle(isCurrentMonth ? Color.primary : Color.secondary)
        }
    }
    
    private func monthlyComparisonPill(comparison: ListeningStatsStore.MonthlyComparison) -> some View {
        HStack(spacing: 6) {
            if comparison.previousMonthHours > 0 {
                let delta = comparison.hoursDelta
                let isUp = delta >= 0
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isUp ? Color.green : Color.orange)
                
                Text(String(format: "%@%.1fh vs %@", isUp ? "+" : "", delta, comparison.previousMonthName))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isUp ? Color.green : Color.orange)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(String(format: "%.1fh listened in %@", comparison.currentMonthHours, comparison.currentMonthName))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
    
    // MARK: - Total Stats View
    
    private var totalStatsView: some View {
        let total = statsStore.totalBreakdown(from: allItems)
        
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                totalMetricTile(value: "\(total.months)", unit: "MONTHS")
                totalMetricTile(value: "\(total.days)", unit: "DAYS")
                totalMetricTile(value: "\(total.hours)", unit: "HOURS")
                totalMetricTile(value: "\(total.minutes)", unit: "MINS")
            }
            
            HStack {
                Text("\(completedBooksCount) Finished • \(inProgressBooksCount) In Progress")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                Text(String(format: "%.1f total hours", total.totalHours))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 4)
    }
    
    private func totalMetricTile(value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            
            Text(unit)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
        }
    }
    
    // MARK: - Daily Goal Card
    
    private var dailyGoalCard: some View {
        let goal = statsStore.dailyGoalProgress(goalMinutes: dailyGoalMinutes, from: allItems)
        let progressFraction = goal.fraction
        let isAccomplished = goal.isAccomplished
        
        return Button {
            isShowingGoalEditor = true
        } label: {
            LiquidGlassCard(cornerRadius: 18, tint: isAccomplished ? .green : .accentColor) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Daily Listening Goal", systemImage: isAccomplished ? "checkmark.seal.fill" : "target")
                            .font(.headline)
                            .foregroundStyle(isAccomplished ? Color.green : Color.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("\(dailyGoalMinutes) min")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isAccomplished ? Color.green : Color.accentColor)
                            
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle((isAccomplished ? Color.green : Color.accentColor).opacity(0.85))
                        }
                    }
                    
                    // Progress Bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: isAccomplished ? [Color.green, Color.mint] : [Color.accentColor, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0.0, geo.size.width * CGFloat(progressFraction)))
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text(isAccomplished ? "Daily goal accomplished! (\(goal.listenedMinutes) min)" : "\(goal.listenedMinutes) \(goal.listenedMinutes == 1 ? "minute" : "minutes") listened today")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(progressFraction * 100))%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isAccomplished ? Color.green : Color.accentColor)
                        }
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
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
    
    private var completedBooksCount: Int {
        allItems.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && $0.isCompleted }.count
    }
    
    private var inProgressBooksCount: Int {
        allItems.filter { $0.kind != .folder && $0.parent?.kind != .multiPart && !$0.isCompleted && $0.currentPosition > 0 && !$0.isDeletedFromLibrary }.count
    }
}

// MARK: - Daily Goal Editor Sheet

/// Interactive sheet for configuring daily audiobook listening target in minutes.
public struct DailyGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goalMinutes: Int
    
    @State private var selectedMinutes: Int
    @State private var customText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private let presets: [Int] = [15, 30, 45, 60, 90, 120]
    
    public init(goalMinutes: Binding<Int>) {
        self._goalMinutes = goalMinutes
        self._selectedMinutes = State(initialValue: goalMinutes.wrappedValue)
        self._customText = State(initialValue: "\(goalMinutes.wrappedValue)")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current Target Callout
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(selectedMinutes)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
                            Text("min / day")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.secondary)
                        }
                        
                        Text(verbalizedGoal)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.top, 12)
                    
                    // Popular Preset Chips
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Popular Goals")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                            ForEach(presets, id: \.self) { preset in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        selectedMinutes = preset
                                        customText = "\(preset)"
                                        isTextFieldFocused = false
                                    }
                                } label: {
                                    Text("\(preset) min")
                                        .font(.subheadline.weight(selectedMinutes == preset ? .bold : .medium))
                                        .foregroundStyle(selectedMinutes == preset ? Color.white : Color.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background {
                                            if selectedMinutes == preset {
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color.accentColor, Color.purple],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                            } else {
                                                Capsule()
                                                    .fill(Color.secondary.opacity(0.12))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Stepper & Direct Keyboard Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Duration")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 4)
                        
                        LiquidGlassCard(cornerRadius: 16) {
                            HStack {
                                Button {
                                    adjustGoal(by: -5)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(selectedMinutes > 5 ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedMinutes <= 5)
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    TextField("Minutes", text: $customText)
                                        #if os(iOS) || os(tvOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .focused($isTextFieldFocused)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .frame(width: 80)
                                        .onChange(of: customText) { _, newValue in
                                            let filtered = newValue.filter { $0.isNumber }
                                            if let val = Int(filtered), val > 0 {
                                                selectedMinutes = min(val, 720)
                                            }
                                        }
                                    
                                    Text("min")
                                        .font(.headline)
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    adjustGoal(by: 5)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(selectedMinutes < 720 ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedMinutes >= 720)
                            }
                            .padding(14)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Daily Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goalMinutes = max(5, selectedMinutes)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.height(420), .medium])
        .presentationDragIndicator(.visible)
    }
    
    private var verbalizedGoal: String {
        let h = selectedMinutes / 60
        let m = selectedMinutes % 60
        if h > 0 && m > 0 {
            return "\(h) hr \(m) min per day"
        } else if h > 0 {
            return "\(h) hr per day"
        } else {
            return "\(m) minutes per day"
        }
    }
    
    private func adjustGoal(by delta: Int) {
        let newGoal = max(5, min(720, selectedMinutes + delta))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedMinutes = newGoal
            customText = "\(newGoal)"
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: LibraryItem.self, inMemory: true)
}

#Preview("Daily Goal Editor") {
    @Previewable @State var goal = 45
    DailyGoalEditorSheet(goalMinutes: $goal)
}
