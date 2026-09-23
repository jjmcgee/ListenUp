import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Service for persisting and aggregating daily audiobook listening activity.
///
/// Tracks listening seconds per day and calculates metrics for Audible-style Listening Stats:
/// - **Today**: Hours and minutes listened today (spans exactly 1 calendar day, resetting to 0 at 00:00).
/// - **Monthly**: Listening hours for previous calendar month and current calendar month.
/// - **Total**: Complete listening time broken down into Months, Days, Hours, and Minutes.
@Observable
@MainActor
public final class ListeningStatsStore {
    
    public static let shared = ListeningStatsStore()
    
    private let userDefaultsKey = "listenup_daily_listening_v1"
    private var dailyRecords: [String: Double] = [:]
    
    /// Observable key for the current calendar day (e.g. "2026-09-21").
    /// Changing this key triggers immediate UI re-render at midnight.
    public private(set) var currentDayKey: String = ""
    
    @ObservationIgnored private var midnightTimer: Timer?
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []
    
    private let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()
    
    private let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()
    
    private let monthDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    public init() {
        self.currentDayKey = dayDateFormatter.string(from: Date())
        loadRecords()
        setupDayRolloverObservers()
        scheduleMidnightTimer()
        syncToWidgets()
    }
    
    /// Stops the midnight timer and removes notification observers.
    public func stopMonitoring() {
        midnightTimer?.invalidate()
        midnightTimer = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    // MARK: - Day Rollover Engine
    
    private func setupDayRolloverObservers() {
        let center = NotificationCenter.default
        let dayObserver = center.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDayChanged()
            }
        }
        notificationObservers.append(dayObserver)
        
        #if canImport(UIKit)
        let timeObserver = center.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDayChanged()
            }
        }
        notificationObservers.append(timeObserver)
        
        let foregroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDayChanged()
            }
        }
        notificationObservers.append(foregroundObserver)
        #endif
    }
    
    /// Called when the calendar day advances past midnight (00:00).
    public func handleDayChanged() {
        dayDateFormatter.timeZone = .autoupdatingCurrent
        monthKeyFormatter.timeZone = .autoupdatingCurrent
        monthDisplayFormatter.timeZone = .autoupdatingCurrent
        currentDayKey = dayDateFormatter.string(from: Date())
        scheduleMidnightTimer()
        syncToWidgets()
    }
    
    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) {
            let interval = nextMidnight.timeIntervalSince(now)
            if interval > 0 {
                midnightTimer = Timer.scheduledTimer(withTimeInterval: interval + 0.2, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleDayChanged()
                    }
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.dailyRecords = decoded
        } else if let legacyDict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] {
            self.dailyRecords = legacyDict
        }
    }
    
    private func saveRecords() {
        if let data = try? JSONEncoder().encode(dailyRecords) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    // MARK: - Recording
    
    /// Records elapsed listening seconds for today (or a specific date).
    public func recordListening(seconds: Double, on date: Date = Date()) {
        guard seconds > 0, !seconds.isNaN, !seconds.isInfinite, seconds < 3600 else { return }
        let key = dayDateFormatter.string(from: date)
        let existing = dailyRecords[key] ?? 0.0
        dailyRecords[key] = existing + seconds
        currentDayKey = dayDateFormatter.string(from: Date())
        saveRecords()
        syncToWidgets()
    }
    
    /// Pushes current listening statistics to WidgetDataStore for WidgetKit display.
    public func syncToWidgets(dailyGoalMinutes: Int = 30, items: [LibraryItem] = []) {
        let todaySecs = todayListeningSeconds(from: items)
        let monthly = monthlyComparison(from: items)
        let total = totalBreakdown(from: items)
        WidgetDataStore.shared.syncStats(
            todaySeconds: todaySecs,
            dailyGoalMinutes: dailyGoalMinutes,
            monthly: monthly,
            total: total
        )
    }
    
    /// Resets all recorded listening history (useful for tests and debug).
    public func resetRecords() {
        dailyRecords.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        currentDayKey = dayDateFormatter.string(from: Date())
        syncToWidgets()
    }
    
    // MARK: - Today Stats
    
    /// Returns today's listened seconds (strictly for the current calendar day).
    /// As soon as the day turns over at 00:00, this resets to 0.
    public func todayListeningSeconds(from items: [LibraryItem] = []) -> Double {
        _ = currentDayKey
        let todayKey = dayDateFormatter.string(from: Date())
        if todayKey != currentDayKey {
            Task { @MainActor [weak self] in
                self?.handleDayChanged()
            }
        }
        return dailyRecords[todayKey] ?? 0.0
    }
    
    /// Returns (hours, minutes) listened today.
    public func todayHoursAndMinutes(from items: [LibraryItem] = []) -> (hours: Int, minutes: Int) {
        let totalSecs = Int(todayListeningSeconds(from: items))
        let totalMinutes = totalSecs / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return (hours, minutes)
    }
    
    // MARK: - Daily Goal Progress
    
    /// Snapshot of progress towards a daily listening goal.
    public struct DailyGoalProgress: Equatable, Sendable {
        public let listenedMinutes: Int
        public let goalMinutes: Int
        public let fraction: Double
        public let isAccomplished: Bool
        public let remainingMinutes: Int
        
        public var percentageText: String {
            "\(Int(fraction * 100))%"
        }
    }
    
    /// Returns progress towards the specified daily listening target for the current day.
    /// Strictly resets to 0 minutes (0%) and unaccomplished as soon as the day rolls over past 00:00.
    public func dailyGoalProgress(goalMinutes: Int, from items: [LibraryItem] = []) -> DailyGoalProgress {
        let (hours, mins) = todayHoursAndMinutes(from: items)
        let listened = (hours * 60) + mins
        let goal = max(1, goalMinutes)
        let fraction = min(1.0, max(0.0, Double(listened) / Double(goal)))
        let remaining = max(0, goal - listened)
        return DailyGoalProgress(
            listenedMinutes: listened,
            goalMinutes: goal,
            fraction: fraction,
            isAccomplished: fraction >= 1.0,
            remainingMinutes: remaining
        )
    }
    
    // MARK: - Monthly Stats (Previous Month & Current Month)
    
    public struct MonthlyComparison: Equatable, Sendable {
        public let previousMonthName: String
        public let currentMonthName: String
        public let previousMonthHours: Double
        public let currentMonthHours: Double
        
        public var hoursDelta: Double {
            currentMonthHours - previousMonthHours
        }
        
        public var percentageChange: Double? {
            guard previousMonthHours > 0 else { return nil }
            return ((currentMonthHours - previousMonthHours) / previousMonthHours) * 100.0
        }
    }
    
    /// Computes listening hours for the previous calendar month and the current calendar month.
    public func monthlyComparison(from items: [LibraryItem] = []) -> MonthlyComparison {
        _ = currentDayKey
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        
        let currentMonthKey = monthKeyFormatter.string(from: now)
        let currentMonthName = monthDisplayFormatter.string(from: now)
        
        let prevDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let prevMonthKey = monthKeyFormatter.string(from: prevDate)
        let prevMonthName = monthDisplayFormatter.string(from: prevDate)
        
        var currentMonthSeconds: Double = 0.0
        var prevMonthSeconds: Double = 0.0
        
        for (dayKey, seconds) in dailyRecords {
            if dayKey.hasPrefix(currentMonthKey) {
                currentMonthSeconds += seconds
            } else if dayKey.hasPrefix(prevMonthKey) {
                prevMonthSeconds += seconds
            }
        }
        
        // Fallback from LibraryItem timestamps if daily records are empty
        if currentMonthSeconds == 0.0 && prevMonthSeconds == 0.0 && !items.isEmpty {
            for item in items {
                let checkDate = item.completedDate ?? item.lastUpdated
                if calendar.isDate(checkDate, equalTo: now, toGranularity: .month) {
                    currentMonthSeconds += min(item.currentPosition, 3600.0 * 20)
                } else if calendar.isDate(checkDate, equalTo: prevDate, toGranularity: .month) {
                    prevMonthSeconds += min(item.currentPosition, 3600.0 * 20)
                }
            }
        }
        
        let currentHours = currentMonthSeconds / 3600.0
        let prevHours = prevMonthSeconds / 3600.0
        
        return MonthlyComparison(
            previousMonthName: prevMonthName,
            currentMonthName: currentMonthName,
            previousMonthHours: prevHours,
            currentMonthHours: currentHours
        )
    }
    
    // MARK: - Total Breakdown
    
    public struct TotalListeningBreakdown: Equatable, Sendable {
        public let months: Int
        public let days: Int
        public let hours: Int
        public let minutes: Int
        public let totalSeconds: Double
        
        public var totalHours: Double {
            totalSeconds / 3600.0
        }
        
        public var formattedSummary: String {
            if months > 0 {
                return "\(months)m \(days)d \(hours)h \(minutes)m"
            } else if days > 0 {
                return "\(days)d \(hours)h \(minutes)m"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
    
    /// Computes lifetime listening partitioned into Months (30 days), Days, Hours, and Minutes.
    public func totalBreakdown(from items: [LibraryItem] = []) -> TotalListeningBreakdown {
        let itemsTotal = items.reduce(0.0) { sum, item in
            sum + max(0.0, item.currentPosition)
        }
        let recordsTotal = dailyRecords.values.reduce(0.0, +)
        let totalSeconds = max(itemsTotal, recordsTotal)
        
        let totalSecs = Int(totalSeconds)
        let secondsInDay = 86400
        let secondsInMonth = 30 * secondsInDay // 30-day standard month
        
        let months = totalSecs / secondsInMonth
        let remAfterMonths = totalSecs % secondsInMonth
        let days = remAfterMonths / secondsInDay
        let remAfterDays = remAfterMonths % secondsInDay
        let hours = remAfterDays / 3600
        let minutes = (remAfterDays % 3600) / 60
        
        return TotalListeningBreakdown(
            months: months,
            days: days,
            hours: hours,
            minutes: minutes,
            totalSeconds: totalSeconds
        )
    }
}
