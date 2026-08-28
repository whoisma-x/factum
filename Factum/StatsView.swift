//
//  StatsView.swift
//  Pigeon
//
//  Study stats with date navigation, donut charts, stacked bar charts,
//  monthly/yearly views, and long-press day detail.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Stats View Mode

enum StatsViewMode: String, CaseIterable {
    case daily = "Day"
    case weekly = "Week"
    case monthly = "Month"
    case yearly = "Year"
    case lifetime = "Lifetime"
}

// MARK: - Stats View

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var selectedMode: StatsViewMode = .daily
    @State private var referenceDate = Date()
    
    private let calendar = Calendar.current
    
    private var userTimelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    // MARK: Filtered data for current period
    
    private var filteredTimelapses: [StudyTimelapse] {
        switch selectedMode {
        case .daily:
            let dayStart = calendar.startOfDay(for: referenceDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            return userTimelapses.filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }
        case .weekly:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
            return userTimelapses.filter { $0.createdAt >= weekInterval.start && $0.createdAt < weekInterval.end }
        case .monthly:
            guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else { return [] }
            return userTimelapses.filter { $0.createdAt >= monthInterval.start && $0.createdAt < monthInterval.end }
        case .yearly:
            guard let yearInterval = calendar.dateInterval(of: .year, for: referenceDate) else { return [] }
            return userTimelapses.filter { $0.createdAt >= yearInterval.start && $0.createdAt < yearInterval.end }
        case .lifetime:
            return userTimelapses
        }
    }
    
    // MARK: Date label
    
    private var dateLabel: String {
        switch selectedMode {
        case .daily:
            if calendar.isDateInToday(referenceDate) { return "Today" }
            if calendar.isDateInYesterday(referenceDate) { return "Yesterday" }
            return referenceDate.formatted(.dateTime.month(.wide).day().year())
        case .weekly:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return "" }
            let end = calendar.date(byAdding: .day, value: -1, to: weekInterval.end)!
            let startStr = weekInterval.start.formatted(.dateTime.month(.abbreviated).day())
            let endStr = end.formatted(.dateTime.month(.abbreviated).day())
            return "\(startStr) – \(endStr)"
        case .monthly:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        case .yearly:
            return referenceDate.formatted(.dateTime.year())
        case .lifetime:
            return "All Time"
        }
    }

    private var canGoForward: Bool {
        switch selectedMode {
        case .daily:
            return !calendar.isDateInToday(referenceDate)
        case .weekly:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
                  let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return false }
            return weekInterval.start < currentWeek.start
        case .monthly:
            let refMonth = calendar.component(.month, from: referenceDate)
            let refYear = calendar.component(.year, from: referenceDate)
            let curMonth = calendar.component(.month, from: Date())
            let curYear = calendar.component(.year, from: Date())
            return refYear < curYear || (refYear == curYear && refMonth < curMonth)
        case .yearly:
            return calendar.component(.year, from: referenceDate) < calendar.component(.year, from: Date())
        case .lifetime:
            return false
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Inline title with back button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 36, height: 36)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(Circle())
                    }
                    
                    Text("Study Stats")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Mode picker
                modePicker
                
                // Date navigation
                dateNavigator
                
                // Chart
                switch selectedMode {
                case .daily:
                    DailyStatsView(timelapses: filteredTimelapses, subjects: subjects, referenceDate: referenceDate)
                case .weekly:
                    WeeklyStatsView(timelapses: filteredTimelapses, subjects: subjects, referenceDate: referenceDate)
                case .monthly:
                    MonthlyStatsView(timelapses: filteredTimelapses, subjects: subjects, referenceDate: referenceDate)
                case .yearly:
                    YearlyStatsView(timelapses: filteredTimelapses, subjects: subjects, referenceDate: referenceDate)
                case .lifetime:
                    LifetimeStatsView(timelapses: filteredTimelapses, subjects: subjects)
                }

                // Summary
                summaryStats
            }
            .padding(.bottom, 100)
        }
        .background(PigeonTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
    
    // MARK: - Mode Picker
    
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                        referenceDate = Date()
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(PigeonTheme.font(12, weight: selectedMode == mode ? .semibold : .regular))
                        .foregroundStyle(selectedMode == mode ? PigeonTheme.accentText : PigeonTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedMode == mode ? PigeonTheme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Date Navigator
    
    private var dateNavigator: some View {
        HStack {
            if selectedMode != .lifetime {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .frame(width: 36, height: 36)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(Circle())
                }
            }

            Spacer()

            Text(dateLabel)
                .font(PigeonTheme.subheadlineFont)
                .foregroundStyle(PigeonTheme.primaryText)

            Spacer()

            if selectedMode != .lifetime {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { navigateForward() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canGoForward ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                        .frame(width: 36, height: 36)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(Circle())
                }
                .disabled(!canGoForward)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func navigateBack() {
        switch selectedMode {
        case .daily:
            referenceDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        case .weekly:
            referenceDate = calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate) ?? referenceDate
        case .monthly:
            referenceDate = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
        case .yearly:
            referenceDate = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
        case .lifetime:
            break
        }
    }

    private func navigateForward() {
        guard canGoForward else { return }
        switch selectedMode {
        case .daily:
            referenceDate = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        case .weekly:
            referenceDate = calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate) ?? referenceDate
        case .monthly:
            referenceDate = calendar.date(byAdding: .month, value: 1, to: referenceDate) ?? referenceDate
        case .yearly:
            referenceDate = calendar.date(byAdding: .year, value: 1, to: referenceDate) ?? referenceDate
        case .lifetime:
            break
        }
    }
    
    // MARK: - Summary Stats
    
    private var summaryStats: some View {
        let totalSeconds = filteredTimelapses.reduce(0) { $0 + $1.durationSeconds }
        let sessionCount = filteredTimelapses.count
        let uniqueSubjects = Set(filteredTimelapses.flatMap { $0.subjectSegments.map(\.subject) }).count
        let totalLeaves = filteredTimelapses.reduce(0) { $0 + $1.appLeaveCount }
        let avgPerSession = sessionCount > 0 ? Double(totalLeaves) / Double(sessionCount) : 0
        let totalHours = Double(totalSeconds) / 3600.0
        let avgLeavesPerHour = totalHours > 0 ? Double(totalLeaves) / totalHours : 0
        let longestSession = filteredTimelapses.max(by: { $0.durationSeconds < $1.durationSeconds })?.durationSeconds ?? 0
        let mostLeavesInSession = filteredTimelapses.max(by: { $0.appLeaveCount < $1.appLeaveCount })?.appLeaveCount ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)

            HStack(spacing: 12) {
                summaryCard(value: formatDuration(totalSeconds), label: "Total Time")
                summaryCard(value: "\(sessionCount)", label: "Sessions")
                summaryCard(value: "\(uniqueSubjects)", label: "Subjects")
            }

            HStack(spacing: 12) {
                summaryCard(value: "\(totalLeaves)", label: "App Leaves")
                    .overlay(
                        RoundedRectangle(cornerRadius: PigeonTheme.cornerCard)
                            .strokeBorder(totalLeaves == 0 ? .green.opacity(0.3) : .red.opacity(0.3), lineWidth: 1)
                    )
                summaryCard(value: String(format: "%.1f", avgPerSession), label: "Avg/Session")
                summaryCard(value: String(format: "%.1f", avgLeavesPerHour), label: "Avg/Hour")
            }

            HStack(spacing: 12) {
                summaryCard(value: formatDuration(longestSession), label: "Longest Session")
                summaryCard(value: "\(mostLeavesInSession)", label: "Most Leaves")
            }

            // Most studied highlights
            mostStudiedSection
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Most Studied Highlights
    
    private var mostStudiedSection: some View {
        let highlights = computeMostStudied()
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Most Studied")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)
                .padding(.top, 8)
            
            ForEach(highlights, id: \.label) { item in
                HStack(spacing: 12) {
                    Text(item.label)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .frame(width: 52, alignment: .leading)
                    
                    Text(item.dateString)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    Spacer()
                    
                    Text(formatDuration(item.seconds))
                        .font(PigeonTheme.font(15, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private struct MostStudiedItem {
        let label: String
        let dateString: String
        let seconds: Int
    }
    
    private func computeMostStudied() -> [MostStudiedItem] {
        guard !userTimelapses.isEmpty else { return [] }
        var items: [MostStudiedItem] = []
        
        // Most studied day
        let byDay = Dictionary(grouping: userTimelapses) { calendar.startOfDay(for: $0.createdAt) }
        if let (bestDay, dayTimelapses) = byDay.max(by: { $0.value.reduce(0) { $0 + $1.durationSeconds } < $1.value.reduce(0) { $0 + $1.durationSeconds } }) {
            let secs = dayTimelapses.reduce(0) { $0 + $1.durationSeconds }
            let dateStr: String
            if calendar.isDateInToday(bestDay) {
                dateStr = "Today"
            } else if calendar.isDateInYesterday(bestDay) {
                dateStr = "Yesterday"
            } else {
                dateStr = bestDay.formatted(.dateTime.month(.abbreviated).day().year())
            }
            items.append(MostStudiedItem(label: "Day", dateString: dateStr, seconds: secs))
        }
        
        // Most studied week
        let byWeek = Dictionary(grouping: userTimelapses) { t -> Date in
            calendar.dateInterval(of: .weekOfYear, for: t.createdAt)?.start ?? t.createdAt
        }
        if let (weekStart, weekTimelapses) = byWeek.max(by: { $0.value.reduce(0) { $0 + $1.durationSeconds } < $1.value.reduce(0) { $0 + $1.durationSeconds } }) {
            let secs = weekTimelapses.reduce(0) { $0 + $1.durationSeconds }
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            let startStr = weekStart.formatted(.dateTime.month(.abbreviated).day())
            let endStr = weekEnd.formatted(.dateTime.month(.abbreviated).day())
            items.append(MostStudiedItem(label: "Week", dateString: "\(startStr) – \(endStr)", seconds: secs))
        }
        
        // Most studied month
        let byMonth = Dictionary(grouping: userTimelapses) { t -> DateComponents in
            calendar.dateComponents([.year, .month], from: t.createdAt)
        }
        if let (monthComps, monthTimelapses) = byMonth.max(by: { $0.value.reduce(0) { $0 + $1.durationSeconds } < $1.value.reduce(0) { $0 + $1.durationSeconds } }) {
            let secs = monthTimelapses.reduce(0) { $0 + $1.durationSeconds }
            if let monthDate = calendar.date(from: monthComps) {
                let dateStr = monthDate.formatted(.dateTime.month(.wide).year())
                items.append(MostStudiedItem(label: "Month", dateString: dateStr, seconds: secs))
            }
        }
        
        // Most studied year
        let byYear = Dictionary(grouping: userTimelapses) { t -> Int in
            calendar.component(.year, from: t.createdAt)
        }
        if let (year, yearTimelapses) = byYear.max(by: { $0.value.reduce(0) { $0 + $1.durationSeconds } < $1.value.reduce(0) { $0 + $1.durationSeconds } }) {
            let secs = yearTimelapses.reduce(0) { $0 + $1.durationSeconds }
            items.append(MostStudiedItem(label: "Year", dateString: "\(year)", seconds: secs))
        }
        
        return items
    }
    
    private func summaryCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(PigeonTheme.font(18, weight: .bold))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerCard))
        .shadow(color: PigeonTheme.cardShadow, radius: PigeonTheme.cardShadowRadius, x: 0, y: PigeonTheme.cardShadowY)
    }
}

// MARK: - Shared Helpers

func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "0m"
}

func subjectBreakdown(from timelapses: [StudyTimelapse], subjects: [StudySubject]) -> [(subject: String, seconds: Int, color: Color)] {
    var dict: [String: Int] = [:]
    for t in timelapses {
        // Use per-subject segments when available; falls back to single segment
        for segment in t.subjectSegments {
            dict[segment.subject, default: 0] += segment.seconds
        }
    }
    return dict.map { (subject: $0.key, seconds: $0.value, color: StudySubject.color(for: $0.key, in: subjects)) }
        .sorted { $0.seconds > $1.seconds }
}

// MARK: - Period Detail Popover (reused by Weekly, Monthly, Yearly)

struct PeriodDetailPopover: View {
    let title: String
    let items: [(subject: String, seconds: Int, percent: Int, color: Color)]
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            
            ForEach(items, id: \.subject) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    Text(item.subject)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    Text("\(item.percent)%")
                        .font(PigeonTheme.font(15, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text(formatDuration(item.seconds))
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(PigeonTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

func buildBreakdown(from timelapses: [StudyTimelapse], subjects: [StudySubject]) -> [(subject: String, seconds: Int, percent: Int, color: Color)] {
    var dict: [String: Int] = [:]
    for t in timelapses {
        for segment in t.subjectSegments {
            dict[segment.subject, default: 0] += segment.seconds
        }
    }
    let totalSec = dict.values.reduce(0, +)
    return dict.map { (subject: $0.key, seconds: $0.value, percent: totalSec > 0 ? Int(Double($0.value) / Double(totalSec) * 100) : 0, color: StudySubject.color(for: $0.key, in: subjects)) }
        .sorted { $0.percent > $1.percent }
}

// MARK: - Donut Chart Content (no outer card chrome — used inside SwipeableCard)

struct DonutChartContent: View {
    let breakdown: [(subject: String, seconds: Int, color: Color)]
    let centerLabel: String
    
    private var totalSeconds: Int {
        breakdown.reduce(0) { $0 + $1.seconds }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if breakdown.isEmpty {
                emptyState
            } else {
                ZStack {
                    Chart(breakdown, id: \.subject) { item in
                        SectorMark(
                            angle: .value("Time", item.seconds),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(item.color)
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 240)
                    
                    VStack(spacing: 4) {
                        Text(formatDuration(totalSeconds))
                            .font(PigeonTheme.font(22, weight: .bold))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text(centerLabel)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                
                // Legend
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(breakdown, id: \.subject) { item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.color)
                                .frame(width: 14, height: 14)
                            
                            Text(item.subject)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            
                            Spacer()
                            
                            let percent = totalSeconds > 0 ? Int(Double(item.seconds) / Double(totalSeconds) * 100) : 0
                            Text("\(formatDuration(item.seconds)) (\(percent)%)")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundStyle(PigeonTheme.tertiaryText)
            Text("No study sessions")
                .font(PigeonTheme.subheadlineFont)
                .foregroundStyle(PigeonTheme.secondaryText)
            Text("Start a session to see your breakdown")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Donut Chart (standalone card — used by DailyStatsView)

struct DonutChartView: View {
    let breakdown: [(subject: String, seconds: Int, color: Color)]
    let centerLabel: String
    
    var body: some View {
        DonutChartContent(breakdown: breakdown, centerLabel: centerLabel)
            .background(PigeonTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
    }
}

// MARK: - Daily Stats View

struct DailyStatsView: View {
    let timelapses: [StudyTimelapse]
    let subjects: [StudySubject]
    let referenceDate: Date

    var body: some View {
        SwipeableCard(
            { dailyDonut },
            page1: { dailyLeavesPerHour }
        )
    }

    private var dailyDonut: some View {
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        let label = Calendar.current.isDateInToday(referenceDate) ? "today" : referenceDate.formatted(.dateTime.month(.abbreviated).day())
        return DonutChartContent(breakdown: bd, centerLabel: label)
    }

    private var dailyLeavesPerHour: some View {
        let data: [(date: Date, rate: Double)] = timelapses.map { t in
            let hours = Double(t.durationSeconds) / 3600.0
            let rate = hours > 0 ? Double(t.appLeaveCount) / hours : 0
            return (date: t.createdAt, rate: rate)
        }.sorted { $0.date < $1.date }
        return AppLeavesPerHourChartContent(data: data)
    }
}

// MARK: - Weekly Stats View (Stacked Bar Chart + Long Press)

struct WeeklyStatsView: View {
    let timelapses: [StudyTimelapse]
    let subjects: [StudySubject]
    let referenceDate: Date
    @State private var selectedDay: Date?
    
    private let calendar = Calendar.current
    
    private var chartData: [WeeklyChartEntry] {
        var entries: [WeeklyChartEntry] = []
        let grouped = Dictionary(grouping: timelapses) { t in
            calendar.startOfDay(for: t.createdAt)
        }
        for (day, dayTimelapses) in grouped {
            var subjectTotals: [String: Int] = [:]
            for t in dayTimelapses {
                for segment in t.subjectSegments {
                    subjectTotals[segment.subject, default: 0] += segment.seconds
                }
            }
            for (subject, seconds) in subjectTotals {
                entries.append(WeeklyChartEntry(
                    day: day, subject: subject, minutes: seconds / 60,
                    color: StudySubject.color(for: subject, in: subjects)
                ))
            }
        }
        return entries.sorted { $0.day < $1.day }
    }
    
    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }
    
    private var totalMinutes: Int {
        timelapses.reduce(0) { $0 + $1.durationSeconds } / 60
    }
    
    /// Switch Y-axis to hours when any single day has 90+ minutes
    private var useHours: Bool {
        let grouped = Dictionary(grouping: chartData, by: { calendar.startOfDay(for: $0.day) })
        return grouped.values.contains { dayEntries in
            dayEntries.reduce(0) { $0 + $1.minutes } >= 90
        }
    }
    
    // Breakdown for the selected day (long-press)
    private var selectedDayBreakdown: [(subject: String, minutes: Int, percent: Int, color: Color)]? {
        guard let day = selectedDay else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        let dayTimelapses = timelapses.filter { calendar.startOfDay(for: $0.createdAt) == dayStart }
        guard !dayTimelapses.isEmpty else { return nil }
        
        var dict: [String: Int] = [:]
        for t in dayTimelapses {
            for segment in t.subjectSegments {
                dict[segment.subject, default: 0] += segment.seconds
            }
        }
        let totalSec = dict.values.reduce(0, +)
        
        return dict.map { (subject: $0.key, minutes: $0.value / 60, percent: totalSec > 0 ? Int(Double($0.value) / Double(totalSec) * 100) : 0, color: StudySubject.color(for: $0.key, in: subjects)) }
            .sorted { $0.percent > $1.percent }
    }
    
    var body: some View {
        SwipeableCard(
            { weeklyBarChart },
            page1: { weeklyDonut },
            page2: { weeklyLeavesPerHour }
        )
    }

    private var weeklyLeavesPerHour: some View {
        // Aggregate leaves/hr per day of the week
        let grouped = Dictionary(grouping: timelapses) { t in
            calendar.startOfDay(for: t.createdAt)
        }
        let data: [(date: Date, rate: Double)] = grouped.map { day, sessions in
            let totalLeaves = sessions.reduce(0) { $0 + $1.appLeaveCount }
            let totalHours = Double(sessions.reduce(0) { $0 + $1.durationSeconds }) / 3600.0
            let rate = totalHours > 0 ? Double(totalLeaves) / totalHours : 0
            return (date: day, rate: rate)
        }.sorted { $0.date < $1.date }
        return AppLeavesPerHourChartContent(data: data)
    }

    private var weeklyBarChart: some View {
        VStack(spacing: 20) {
            if chartData.isEmpty {
                emptyBarState(message: "No study sessions this week")
            } else {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(totalMinutes / 60)h \(totalMinutes % 60)m")
                            .font(PigeonTheme.font(24, weight: .bold))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("total")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                    Spacer()
                    
                    if selectedDay == nil {
                        Text("Tap bar for details")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                
                // Stacked bar chart
                Chart(chartData) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value(useHours ? "Hours" : "Minutes",
                                  useHours ? Double(entry.minutes) / 60.0 : Double(entry.minutes))
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(4)
                    .opacity(selectedDay == nil || calendar.startOfDay(for: entry.day) == selectedDay ? 1.0 : 0.3)
                }
                .chartXAxis {
                    AxisMarks(values: weekDays) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(PigeonTheme.separator)
                        AxisValueLabel().foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .chartYAxisLabel(useHours ? "hr" : "min", position: .trailing)
                .frame(height: 220)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let origin = geometry[proxy.plotFrame!].origin
                                let adjusted = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                                if let date: Date = proxy.value(atX: adjusted.x) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedDay == calendar.startOfDay(for: date) {
                                            selectedDay = nil
                                        } else {
                                            selectedDay = calendar.startOfDay(for: date)
                                        }
                                    }
                                }
                            }
                    }
                }
                
                // Selected day detail popover
                if let breakdown = selectedDayBreakdown, let day = selectedDay {
                    PeriodDetailPopover(
                        title: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        items: breakdown.map { (subject: $0.subject, seconds: $0.minutes * 60, percent: $0.percent, color: $0.color) },
                        onDismiss: { withAnimation { selectedDay = nil } }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // Legend
                    weeklyLegend
                }
            }
        }
        .padding(16)
    }
    
    private var weeklyDonut: some View {
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        let label = weekStart.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "this week"
        return DonutChartContent(breakdown: bd, centerLabel: label)
    }
    
    private var weeklyLegend: some View {
        let uniqueSubjects = Dictionary(grouping: chartData, by: { $0.subject })
        let sorted = uniqueSubjects.map { (subject: $0.key, totalMinutes: $0.value.reduce(0) { $0 + $1.minutes }, color: $0.value.first?.color ?? .gray) }
            .sorted { $0.totalMinutes > $1.totalMinutes }
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(sorted, id: \.subject) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    Text(item.subject)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    Text("\(item.totalMinutes / 60)h \(item.totalMinutes % 60)m")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
        }
    }
}

// MARK: - Monthly Stats View (Calendar + Donut)

struct MonthlyStatsView: View {
    let timelapses: [StudyTimelapse]
    let subjects: [StudySubject]
    let referenceDate: Date
    @State private var selectedDay: Int?
    private let calendar = Calendar.current
    
    /// Minutes studied per day of month (1-indexed)
    private var dailyMinutes: [Int: Int] {
        var dict: [Int: Int] = [:]
        for t in timelapses {
            let day = calendar.component(.day, from: t.createdAt)
            dict[day, default: 0] += t.durationSeconds / 60
        }
        return dict
    }
    
    /// Max minutes in any single day (for color intensity scaling)
    private var maxMinutes: Int {
        dailyMinutes.values.max() ?? 1
    }
    
    /// Days in the current month
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30
    }
    
    /// Weekday of the 1st (0 = Sunday when firstWeekday=1)
    private var firstWeekdayOffset: Int {
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let firstOfMonth = calendar.date(from: comps) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return weekday - 1
    }
    
    /// Trailing empty cells to fill the last row
    private var trailingEmptyCells: Int {
        let totalCells = firstWeekdayOffset + daysInMonth
        let remainder = totalCells % 7
        return remainder == 0 ? 0 : 7 - remainder
    }
    
    /// Today's day number (if this month contains today)
    private var todayDay: Int? {
        let refMonth = calendar.component(.month, from: referenceDate)
        let refYear = calendar.component(.year, from: referenceDate)
        let nowMonth = calendar.component(.month, from: Date())
        let nowYear = calendar.component(.year, from: Date())
        guard refMonth == nowMonth && refYear == nowYear else { return nil }
        return calendar.component(.day, from: Date())
    }
    
    private let weekdayHeaders: [(id: Int, label: String)] = [
        (0, "S"), (1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S")
    ]
    
    /// Timelapses for the selected day
    private var selectedDayBreakdown: [(subject: String, seconds: Int, percent: Int, color: Color)]? {
        guard let day = selectedDay else { return nil }
        let dayTimelapses = timelapses.filter { calendar.component(.day, from: $0.createdAt) == day }
        guard !dayTimelapses.isEmpty else { return nil }
        return buildBreakdown(from: dayTimelapses, subjects: subjects)
    }
    
    /// Date for the selected day number
    private func dateForDay(_ day: Int) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: referenceDate)
        comps.day = day
        return calendar.date(from: comps)
    }
    
    var body: some View {
        SwipeableCard(
            { calendarGrid },
            page1: { monthlyDonut },
            page2: { monthlyLeavesPerHour }
        )
    }

    private var monthlyLeavesPerHour: some View {
        // Aggregate leaves/hr per day of the month
        let grouped = Dictionary(grouping: timelapses) { t in
            calendar.startOfDay(for: t.createdAt)
        }
        let data: [(date: Date, rate: Double)] = grouped.map { day, sessions in
            let totalLeaves = sessions.reduce(0) { $0 + $1.appLeaveCount }
            let totalHours = Double(sessions.reduce(0) { $0 + $1.durationSeconds }) / 3600.0
            let rate = totalHours > 0 ? Double(totalLeaves) / totalHours : 0
            return (date: day, rate: rate)
        }.sorted { $0.date < $1.date }
        return AppLeavesPerHourChartContent(data: data)
    }

    /// All cells: leading empties + day 1..daysInMonth + trailing empties, grouped into rows of 7.
    private var calendarRows: [[Int?]] {
        var cells: [Int?] = Array(repeating: nil, count: firstWeekdayOffset)
        cells += (1...daysInMonth).map { Optional($0) }
        let trailing = trailingEmptyCells
        cells += Array(repeating: nil as Int?, count: trailing)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 12) {
            // Total for the month
            let totalMin = dailyMinutes.values.reduce(0, +)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDuration(totalMin * 60))
                        .font(PigeonTheme.font(24, weight: .bold))
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text("this month")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                Spacer()
            }
            
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(weekdayHeaders, id: \.id) { item in
                    Text(item.label)
                        .font(PigeonTheme.font(11, weight: .medium))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar rows (non-lazy so all cells are always rendered)
            VStack(spacing: 4) {
                ForEach(Array(calendarRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(0..<row.count, id: \.self) { col in
                            if let day = row[col] {
                                let minutes = dailyMinutes[day] ?? 0
                                let intensity = maxMinutes > 0 ? Double(minutes) / Double(maxMinutes) : 0
                                let isToday = day == todayDay
                                let isSelected = day == selectedDay
                                
                                dayCell(day: day, minutes: minutes, intensity: intensity, isToday: isToday, isSelected: isSelected)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                        }
                    }
                }
            }
            
            // Selected day detail popover
            if let breakdown = selectedDayBreakdown, let day = selectedDay, let date = dateForDay(day) {
                PeriodDetailPopover(
                    title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    items: breakdown,
                    onDismiss: { withAnimation { selectedDay = nil } }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(16)
    }
    
    private func dayCell(day: Int, minutes: Int, intensity: Double, isToday: Bool, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(PigeonTheme.font(16, weight: minutes > 0 || isToday ? .semibold : .light))
                .foregroundStyle(isToday ? PigeonTheme.background : (minutes > 0 ? PigeonTheme.primaryText : PigeonTheme.tertiaryText))
            
            if minutes > 0 {
                Text(minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 > 0 ? " \(minutes % 60)m" : "")" : "\(minutes)m")
                    .font(PigeonTheme.font(8, weight: .medium))
                    .foregroundStyle(isToday ? PigeonTheme.background.opacity(0.7) : PigeonTheme.secondaryText)
            } else {
                Text("")
                    .font(PigeonTheme.font(8))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday
                      ? PigeonTheme.primaryText
                      : (minutes > 0
                         ? PigeonTheme.accent.opacity(0.3 + intensity * 0.7)
                         : PigeonTheme.surfaceBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? PigeonTheme.primaryText : Color.clear, lineWidth: 2)
        )
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedDay == day {
                    selectedDay = nil
                } else {
                    selectedDay = minutes > 0 ? day : nil
                }
            }
        }
    }
    
    private var monthlyDonut: some View {
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        let label = referenceDate.formatted(.dateTime.month(.abbreviated))
        return DonutChartContent(breakdown: bd, centerLabel: label)
    }
}

// MARK: - Yearly Stats View (Bar Chart by Month)

struct YearlyStatsView: View {
    let timelapses: [StudyTimelapse]
    let subjects: [StudySubject]
    let referenceDate: Date
    @State private var selectedMonth: Int?
    
    private let calendar = Calendar.current
    
    private var chartData: [YearlyChartEntry] {
        var entries: [YearlyChartEntry] = []
        let grouped = Dictionary(grouping: timelapses) { t in
            calendar.component(.month, from: t.createdAt)
        }
        for (month, monthTimelapses) in grouped {
            var subjectTotals: [String: Int] = [:]
            for t in monthTimelapses {
                for segment in t.subjectSegments {
                    subjectTotals[segment.subject, default: 0] += segment.seconds
                }
            }
            // Create a date for the 1st of that month for the x-axis
            let year = calendar.component(.year, from: referenceDate)
            let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            for (subject, seconds) in subjectTotals {
                entries.append(YearlyChartEntry(
                    month: monthDate, subject: subject, hours: Double(seconds) / 3600.0,
                    color: StudySubject.color(for: subject, in: subjects)
                ))
            }
        }
        return entries.sorted { $0.month < $1.month }
    }
    
    private var totalHours: Double {
        Double(timelapses.reduce(0) { $0 + $1.durationSeconds }) / 3600.0
    }
    
    // All 12 months for the x-axis
    private var monthDates: [Date] {
        let year = calendar.component(.year, from: referenceDate)
        return (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }
    
    /// Breakdown for the selected month
    private var selectedMonthBreakdown: [(subject: String, seconds: Int, percent: Int, color: Color)]? {
        guard let month = selectedMonth else { return nil }
        let monthTimelapses = timelapses.filter { calendar.component(.month, from: $0.createdAt) == month }
        guard !monthTimelapses.isEmpty else { return nil }
        return buildBreakdown(from: monthTimelapses, subjects: subjects)
    }
    
    /// Date for the selected month
    private func dateForMonth(_ month: Int) -> Date? {
        let year = calendar.component(.year, from: referenceDate)
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }
    
    var body: some View {
        SwipeableCard(
            { yearlyBarChart },
            page1: { yearlyDonut },
            page2: { yearlyLeavesPerHour }
        )
    }

    private var yearlyLeavesPerHour: some View {
        // Aggregate leaves/hr per month of the year
        let grouped = Dictionary(grouping: timelapses) { t in
            calendar.component(.month, from: t.createdAt)
        }
        let year = calendar.component(.year, from: referenceDate)
        let data: [(date: Date, rate: Double)] = grouped.compactMap { month, sessions in
            guard let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            let totalLeaves = sessions.reduce(0) { $0 + $1.appLeaveCount }
            let totalHours = Double(sessions.reduce(0) { $0 + $1.durationSeconds }) / 3600.0
            let rate = totalHours > 0 ? Double(totalLeaves) / totalHours : 0
            return (date: monthDate, rate: rate)
        }.sorted { $0.date < $1.date }
        return AppLeavesPerHourChartContent(data: data, xUnit: .month)
    }

    private var yearlyBarChart: some View {
        VStack(spacing: 20) {
            if chartData.isEmpty {
                emptyBarState(message: "No study sessions this year")
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.0fh", totalHours))
                            .font(PigeonTheme.font(24, weight: .bold))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("total this year")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                    Spacer()
                    
                    if selectedMonth == nil {
                        Text("Tap bar for details")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                
                Chart(chartData) { entry in
                    BarMark(
                        x: .value("Month", entry.month, unit: .month),
                        y: .value("Hours", entry.hours)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(4)
                    .opacity(selectedMonth == nil || calendar.component(.month, from: entry.month) == selectedMonth ? 1.0 : 0.3)
                }
                .chartXAxis {
                    AxisMarks(values: monthDates) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(PigeonTheme.separator)
                        AxisValueLabel().foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .chartYAxisLabel("hours", position: .trailing)
                .frame(height: 220)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let origin = geometry[proxy.plotFrame!].origin
                                let adjusted = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                                if let date: Date = proxy.value(atX: adjusted.x) {
                                    let month = calendar.component(.month, from: date)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedMonth == month {
                                            selectedMonth = nil
                                        } else {
                                            selectedMonth = month
                                        }
                                    }
                                }
                            }
                    }
                }
                
                // Selected month detail popover
                if let breakdown = selectedMonthBreakdown, let month = selectedMonth, let date = dateForMonth(month) {
                    PeriodDetailPopover(
                        title: date.formatted(.dateTime.month(.wide)),
                        items: breakdown,
                        onDismiss: { withAnimation { selectedMonth = nil } }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // Legend
                    yearlyLegend
                }
            }
        }
        .padding(16)
    }
    
    private var yearlyDonut: some View {
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        let year = calendar.component(.year, from: referenceDate)
        return DonutChartContent(breakdown: bd, centerLabel: "\(year)")
    }
    
    private var yearlyLegend: some View {
        let uniqueSubjects = Dictionary(grouping: chartData, by: { $0.subject })
        let sorted = uniqueSubjects.map { (subject: $0.key, totalHours: $0.value.reduce(0.0) { $0 + $1.hours }, color: $0.value.first?.color ?? .gray) }
            .sorted { $0.totalHours > $1.totalHours }
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(sorted, id: \.subject) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    Text(item.subject)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    Text(String(format: "%.1fh", item.totalHours))
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
        }
    }
}

// MARK: - App Leaves Per Hour Chart

struct AppLeavesPerHourChartContent: View {
    let data: [(date: Date, rate: Double)]
    var xUnit: Calendar.Component = .day

    var body: some View {
        VStack(spacing: 20) {
            if data.isEmpty || data.allSatisfy({ $0.rate == 0 }) {
                VStack(spacing: 12) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    Text("No app leaves")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Text("Great focus!")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        let nonZero = data.filter { $0.rate > 0 }
                        let avgRate = nonZero.isEmpty ? 0 : nonZero.reduce(0.0) { $0 + $1.rate } / Double(nonZero.count)
                        Text(String(format: "%.1f", avgRate))
                            .font(PigeonTheme.font(24, weight: .bold))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("avg leaves/hr")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                    Spacer()
                }

                Chart(Array(data.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("Time", item.date, unit: xUnit),
                        y: .value("Leaves/hr", item.rate)
                    )
                    .foregroundStyle(
                        item.rate <= 1.0 ? Color.green :
                        item.rate <= 3.0 ? Color.orange : Color.red
                    )
                    .symbolSize(40)
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(PigeonTheme.separator)
                        AxisValueLabel().foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .chartYAxisLabel("leaves/hr", position: .trailing)
                .frame(height: 220)
            }
        }
        .padding(16)
    }
}

// MARK: - Comparison Palette

private let comparisonPalette: [Color] = [
    Color(hex: "#3478F6")!,   // Blue
    Color(hex: "#FF3B30")!,   // Red
    Color(hex: "#34C759")!,   // Green
    Color(hex: "#FF9500")!,   // Orange
    Color(hex: "#AF52DE")!,   // Purple
    Color(hex: "#5AC8FA")!,   // Teal
    Color(hex: "#FF2D55")!,   // Pink
    Color(hex: "#A2845E")!,   // Brown
    Color(hex: "#FFCC00")!,   // Yellow
    Color(hex: "#00C7BE")!,   // Mint
    Color(hex: "#BF5AF2")!,   // Indigo
    Color(hex: "#64D2FF")!,   // Cyan
]

// MARK: - Lifetime Stats View

struct LifetimeStatsView: View {
    let timelapses: [StudyTimelapse]
    let subjects: [StudySubject]

    private let calendar = Calendar.current

    var body: some View {
        SwipeableCard(
            { subjectDonut },
            page1: { yearComparisonDonut },
            page2: { monthComparisonDonut }
        )
    }

    // Slide 1: All-time subject breakdown donut
    private var subjectDonut: some View {
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        return DonutChartContent(breakdown: bd, centerLabel: "all time")
    }

    // Slide 2: Year comparison donut
    private var yearComparisonDonut: some View {
        let byYear = Dictionary(grouping: timelapses) { t in
            calendar.component(.year, from: t.createdAt)
        }
        let breakdown: [(subject: String, seconds: Int, color: Color)] = byYear
            .map { (year: $0.key, seconds: $0.value.reduce(0) { $0 + $1.durationSeconds }) }
            .sorted { $0.year < $1.year }
            .enumerated()
            .map { index, item in
                (subject: "\(item.year)", seconds: item.seconds, color: comparisonPalette[index % comparisonPalette.count])
            }
        return DonutChartContent(breakdown: breakdown, centerLabel: "by year")
    }

    // Slide 3: Month comparison donut
    private var monthComparisonDonut: some View {
        let byMonth = Dictionary(grouping: timelapses) { t in
            calendar.dateComponents([.year, .month], from: t.createdAt)
        }
        let breakdown: [(subject: String, seconds: Int, color: Color)] = byMonth
            .compactMap { comps, sessions -> (label: String, seconds: Int, sortKey: Date)? in
                guard let date = calendar.date(from: comps) else { return nil }
                let label = date.formatted(.dateTime.month(.abbreviated).year())
                let secs = sessions.reduce(0) { $0 + $1.durationSeconds }
                return (label: label, seconds: secs, sortKey: date)
            }
            .sorted { $0.sortKey < $1.sortKey }
            .enumerated()
            .map { index, item in
                (subject: item.label, seconds: item.seconds, color: comparisonPalette[index % comparisonPalette.count])
            }
        return DonutChartContent(breakdown: breakdown, centerLabel: "by month")
    }
}

// MARK: - Page Height Preference Key

private struct PageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Swipeable Card (N-page container with natural height)

struct SwipeableCard: View {
    let pages: [AnyView]

    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var pageHeights: [Int: CGFloat] = [:]
    @State private var cardWidth: CGFloat = 0

    private var pageCount: Int { pages.count }

    private var activeHeight: CGFloat {
        max(pageHeights[currentPage] ?? 450, 50)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: activeHeight)
                .overlay(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            page
                                .frame(width: max(cardWidth, 1), alignment: .top)
                                .background(GeometryReader { g in
                                    Color.clear.preference(
                                        key: PageHeightPreferenceKey.self,
                                        value: [index: g.size.height]
                                    )
                                })
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * max(cardWidth, 1) + dragOffset)
                }
                .clipped()
                .contentShape(Rectangle())
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { cardWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in cardWidth = w }
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onChanged { value in
                            // Only track clearly horizontal drags so vertical
                            // scrolling passes through to the parent ScrollView
                            if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 60
                            let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if isHorizontal && value.translation.width < -threshold && currentPage < pageCount - 1 {
                                    currentPage += 1
                                } else if isHorizontal && value.translation.width > threshold && currentPage > 0 {
                                    currentPage -= 1
                                }
                                dragOffset = 0
                            }
                        }
                )

            // Page indicators
            if pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == currentPage
                                  ? PigeonTheme.primaryText : PigeonTheme.separator)
                            .frame(width: i == currentPage ? 16 : 6, height: 6)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.15), value: currentPage)
            }
        }
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .onPreferenceChange(PageHeightPreferenceKey.self) { pageHeights = $0 }
        .animation(.easeInOut(duration: 0.25), value: activeHeight)
    }
}

// Convenience initializers for backward compatibility
extension SwipeableCard {
    init<P0: View, P1: View>(
        @ViewBuilder _ page0: () -> P0,
        @ViewBuilder page1: () -> P1
    ) {
        self.init(pages: [AnyView(page0()), AnyView(page1())])
    }

    init<P0: View, P1: View, P2: View>(
        @ViewBuilder _ page0: () -> P0,
        @ViewBuilder page1: () -> P1,
        @ViewBuilder page2: () -> P2
    ) {
        self.init(pages: [AnyView(page0()), AnyView(page1()), AnyView(page2())])
    }
}

// MARK: - Chart Data Models

struct WeeklyChartEntry: Identifiable {
    let id = UUID()
    let day: Date
    let subject: String
    let minutes: Int
    let color: Color
}

struct YearlyChartEntry: Identifiable {
    let id = UUID()
    let month: Date
    let subject: String
    let hours: Double
    let color: Color
}

// MARK: - Shared Empty State

func emptyBarState(message: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "chart.bar")
            .font(.system(size: 40))
            .foregroundStyle(PigeonTheme.tertiaryText)
        Text(message)
            .font(PigeonTheme.subheadlineFont)
            .foregroundStyle(PigeonTheme.secondaryText)
        Text("Start studying to see your progress")
            .font(PigeonTheme.captionFont)
            .foregroundStyle(PigeonTheme.tertiaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
}
