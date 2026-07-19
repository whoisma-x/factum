//
//  StatsView.swift
//  Factum
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
                            .foregroundStyle(FactumTheme.primaryText)
                            .frame(width: 36, height: 36)
                            .background(FactumTheme.cardBackground)
                            .clipShape(Circle())
                    }
                    
                    Text("Study Stats")
                        .font(FactumTheme.titleFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
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
                }
                
                // Summary
                summaryStats
            }
            .padding(.bottom, 100)
        }
        .background(FactumTheme.background)
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
                        .font(FactumTheme.font(13, weight: selectedMode == mode ? .semibold : .regular))
                        .foregroundStyle(selectedMode == mode ? FactumTheme.accentText : FactumTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedMode == mode ? FactumTheme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(FactumTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Date Navigator
    
    private var dateNavigator: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { navigateBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FactumTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(FactumTheme.cardBackground)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text(dateLabel)
                .font(FactumTheme.subheadlineFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { navigateForward() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canGoForward ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                    .frame(width: 36, height: 36)
                    .background(FactumTheme.cardBackground)
                    .clipShape(Circle())
            }
            .disabled(!canGoForward)
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
        }
    }
    
    // MARK: - Summary Stats
    
    private var summaryStats: some View {
        let totalSeconds = filteredTimelapses.reduce(0) { $0 + $1.durationSeconds }
        let sessionCount = filteredTimelapses.count
        let uniqueSubjects = Set(filteredTimelapses.map { $0.subject }).count
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(FactumTheme.headlineFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            HStack(spacing: 12) {
                summaryCard(value: formatDuration(totalSeconds), label: "Total Time")
                summaryCard(value: "\(sessionCount)", label: "Sessions")
                summaryCard(value: "\(uniqueSubjects)", label: "Subjects")
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
                .font(FactumTheme.headlineFont)
                .foregroundStyle(FactumTheme.primaryText)
                .padding(.top, 8)
            
            ForEach(highlights, id: \.label) { item in
                HStack(spacing: 12) {
                    Text(item.label)
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                        .frame(width: 52, alignment: .leading)
                    
                    Text(item.dateString)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    Spacer()
                    
                    Text(formatDuration(item.seconds))
                        .font(FactumTheme.font(15, weight: .semibold))
                        .foregroundStyle(FactumTheme.primaryText)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(FactumTheme.cardBackground)
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
                .font(FactumTheme.font(18, weight: .bold))
                .foregroundStyle(FactumTheme.primaryText)
            Text(label)
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(FactumTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        dict[t.subject, default: 0] += t.durationSeconds
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
                    .font(FactumTheme.subheadlineFont)
                    .foregroundStyle(FactumTheme.primaryText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FactumTheme.tertiaryText)
                }
            }
            
            ForEach(items, id: \.subject) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 14, height: 14)
                    Text(item.subject)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    Spacer()
                    Text("\(item.percent)%")
                        .font(FactumTheme.font(15, weight: .semibold))
                        .foregroundStyle(FactumTheme.primaryText)
                    Text(formatDuration(item.seconds))
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(FactumTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

func buildBreakdown(from timelapses: [StudyTimelapse], subjects: [StudySubject]) -> [(subject: String, seconds: Int, percent: Int, color: Color)] {
    var dict: [String: Int] = [:]
    for t in timelapses { dict[t.subject, default: 0] += t.durationSeconds }
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
                            .font(FactumTheme.font(22, weight: .bold))
                            .foregroundStyle(FactumTheme.primaryText)
                        Text(centerLabel)
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
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
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.primaryText)
                            
                            Spacer()
                            
                            let percent = totalSeconds > 0 ? Int(Double(item.seconds) / Double(totalSeconds) * 100) : 0
                            Text("\(formatDuration(item.seconds)) (\(percent)%)")
                                .font(FactumTheme.captionFont)
                                .foregroundStyle(FactumTheme.secondaryText)
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
                .foregroundStyle(FactumTheme.tertiaryText)
            Text("No study sessions")
                .font(FactumTheme.subheadlineFont)
                .foregroundStyle(FactumTheme.secondaryText)
            Text("Start a session to see your breakdown")
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.tertiaryText)
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
            .background(FactumTheme.cardBackground)
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
        let bd = subjectBreakdown(from: timelapses, subjects: subjects)
        let label = Calendar.current.isDateInToday(referenceDate) ? "today" : referenceDate.formatted(.dateTime.month(.abbreviated).day())
        DonutChartView(breakdown: bd, centerLabel: label)
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
                subjectTotals[t.subject, default: 0] += t.durationSeconds
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
    
    // Breakdown for the selected day (long-press)
    private var selectedDayBreakdown: [(subject: String, minutes: Int, percent: Int, color: Color)]? {
        guard let day = selectedDay else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        let dayTimelapses = timelapses.filter { calendar.startOfDay(for: $0.createdAt) == dayStart }
        guard !dayTimelapses.isEmpty else { return nil }
        
        var dict: [String: Int] = [:]
        for t in dayTimelapses { dict[t.subject, default: 0] += t.durationSeconds }
        let totalSec = dict.values.reduce(0, +)
        
        return dict.map { (subject: $0.key, minutes: $0.value / 60, percent: totalSec > 0 ? Int(Double($0.value) / Double(totalSec) * 100) : 0, color: StudySubject.color(for: $0.key, in: subjects)) }
            .sorted { $0.percent > $1.percent }
    }
    
    var body: some View {
        SwipeableCard {
            weeklyBarChart
        } page1: {
            weeklyDonut
        }
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
                            .font(FactumTheme.font(24, weight: .bold))
                            .foregroundStyle(FactumTheme.primaryText)
                        Text("total")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                    Spacer()
                    
                    if selectedDay == nil {
                        Text("Tap bar for details")
                            .font(FactumTheme.smallFont)
                            .foregroundStyle(FactumTheme.tertiaryText)
                    }
                }
                
                // Stacked bar chart
                Chart(chartData) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Minutes", entry.minutes)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(4)
                    .opacity(selectedDay == nil || calendar.startOfDay(for: entry.day) == selectedDay ? 1.0 : 0.3)
                }
                .chartXAxis {
                    AxisMarks(values: weekDays) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(FactumTheme.separator)
                        AxisValueLabel().foregroundStyle(FactumTheme.tertiaryText)
                    }
                }
                .chartYAxisLabel("min", position: .trailing)
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
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    Spacer()
                    Text("\(item.totalMinutes / 60)h \(item.totalMinutes % 60)m")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
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
        SwipeableCard {
            calendarGrid
        } page1: {
            monthlyDonut
        }
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 12) {
            // Total for the month
            let totalMin = dailyMinutes.values.reduce(0, +)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDuration(totalMin * 60))
                        .font(FactumTheme.font(24, weight: .bold))
                        .foregroundStyle(FactumTheme.primaryText)
                    Text("this month")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                Spacer()
            }
            
            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(weekdayHeaders, id: \.id) { item in
                    Text(item.label)
                        .font(FactumTheme.font(11, weight: .medium))
                        .foregroundStyle(FactumTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
                
                // Leading empty cells
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 52)
                }
                
                // Day cells
                ForEach(1...daysInMonth, id: \.self) { day in
                    let minutes = dailyMinutes[day] ?? 0
                    let intensity = maxMinutes > 0 ? Double(minutes) / Double(maxMinutes) : 0
                    let isToday = day == todayDay
                    let isSelected = day == selectedDay
                    
                    VStack(spacing: 2) {
                        Text("\(day)")
                            .font(FactumTheme.font(18, weight: minutes > 0 || isToday ? .semibold : .light))
                            .foregroundStyle(isToday ? FactumTheme.background : (minutes > 0 ? FactumTheme.primaryText : FactumTheme.tertiaryText))
                        
                        if minutes > 0 {
                            Text(minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 > 0 ? " \(minutes % 60)m" : "")" : "\(minutes)m")
                                .font(FactumTheme.font(9, weight: .medium))
                                .foregroundStyle(isToday ? FactumTheme.background.opacity(0.7) : FactumTheme.secondaryText)
                        } else {
                            Text("")
                                .font(FactumTheme.font(9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isToday
                                  ? FactumTheme.primaryText
                                  : (minutes > 0
                                     ? FactumTheme.accent.opacity(0.3 + intensity * 0.7)
                                     : FactumTheme.surfaceBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? FactumTheme.primaryText : Color.clear, lineWidth: 2)
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
                
                // Trailing empty cells to complete the last row
                ForEach(0..<trailingEmptyCells, id: \.self) { _ in
                    Color.clear
                        .frame(height: 52)
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
                subjectTotals[t.subject, default: 0] += t.durationSeconds
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
        SwipeableCard {
            yearlyBarChart
        } page1: {
            yearlyDonut
        }
    }
    
    private var yearlyBarChart: some View {
        VStack(spacing: 20) {
            if chartData.isEmpty {
                emptyBarState(message: "No study sessions this year")
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.0fh", totalHours))
                            .font(FactumTheme.font(24, weight: .bold))
                            .foregroundStyle(FactumTheme.primaryText)
                        Text("total this year")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                    Spacer()
                    
                    if selectedMonth == nil {
                        Text("Tap bar for details")
                            .font(FactumTheme.smallFont)
                            .foregroundStyle(FactumTheme.tertiaryText)
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
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(FactumTheme.separator)
                        AxisValueLabel().foregroundStyle(FactumTheme.tertiaryText)
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
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    Spacer()
                    Text(String(format: "%.1fh", item.totalHours))
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
            }
        }
    }
}

// MARK: - Height Preference Keys

private struct Height0Key: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct Height1Key: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Swipeable Card (two-page container with natural height)

struct SwipeableCard<Page0: View, Page1: View>: View {
    @ViewBuilder var page0: Page0
    @ViewBuilder var page1: Page1
    
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var height0: CGFloat = 300
    @State private var height1: CGFloat = 300
    @State private var cardWidth: CGFloat = 0
    
    private var progress: CGFloat {
        guard cardWidth > 0 else { return CGFloat(currentPage) }
        guard dragOffset != 0 else { return CGFloat(currentPage) }
        let raw = CGFloat(currentPage) - dragOffset / cardWidth
        return min(1, max(0, raw))
    }
    
    private var interpolatedHeight: CGFloat {
        let h = height0 + (height1 - height0) * progress
        return max(h, 50)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Page indicators
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CGFloat(i) <= progress + 0.5 && CGFloat(i) >= progress - 0.5
                              ? FactumTheme.primaryText : FactumTheme.separator)
                        .frame(width: abs(CGFloat(i) - progress) < 0.5 ? 16 : 6, height: 6)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            .animation(.easeInOut(duration: 0.15), value: progress)
            
            // Measurement layer: both pages rendered at full width, invisible, to capture natural heights
            ZStack {
                page0
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: Height0Key.self, value: g.size.height)
                    })
                
                page1
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: Height1Key.self, value: g.size.height)
                    })
            }
            .frame(height: 0)
            .clipped()
            .allowsHitTesting(false)
            
            // Visible sliding content
            Color.clear
                .frame(height: interpolatedHeight)
                .overlay(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        page0
                            .frame(width: max(cardWidth, 1), alignment: .top)
                        page1
                            .frame(width: max(cardWidth, 1), alignment: .top)
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
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            if abs(value.translation.width) > abs(value.translation.height) {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 60
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if value.translation.width < -threshold && currentPage == 0 {
                                    currentPage = 1
                                } else if value.translation.width > threshold && currentPage == 1 {
                                    currentPage = 0
                                }
                                dragOffset = 0
                            }
                        }
                )
        }
        .background(FactumTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .onPreferenceChange(Height0Key.self) { height0 = $0 }
        .onPreferenceChange(Height1Key.self) { height1 = $0 }
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
            .foregroundStyle(FactumTheme.tertiaryText)
        Text(message)
            .font(FactumTheme.subheadlineFont)
            .foregroundStyle(FactumTheme.secondaryText)
        Text("Start studying to see your progress")
            .font(FactumTheme.captionFont)
            .foregroundStyle(FactumTheme.tertiaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
}
