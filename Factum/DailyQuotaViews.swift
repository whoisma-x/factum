//
//  DailyQuotaViews.swift
//  Pigeon
//
//  Add / Edit sheets for study quotas
//

import SwiftUI
import SwiftData

// MARK: - Helpers

/// Dark green brand accent for quotas.
let quotaGreen = Color(red: 0.18, green: 0.42, blue: 0.22)

/// Formats a minute count as "Xh Ym", "Xh", or "Ym" — never decimals.
func formatQuotaTime(_ totalMinutes: Int) -> String {
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

// MARK: - Ruler Slider

/// UIKit pan gesture wrapper that only recognizes horizontal drags.
/// This lets vertical scrolls pass through to the parent ScrollView.
/// Uses a continuous pixel offset so the ruler physically slides on snap.
private struct HorizontalDragView: UIViewRepresentable {
    @Binding var value: Int
    @Binding var pixelOffset: CGFloat
    let range: ClosedRange<Int>
    let tickSpacing: CGFloat
    let onSnap: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.range = range
        context.coordinator.tickSpacing = tickSpacing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: HorizontalDragView
        var range: ClosedRange<Int>
        var tickSpacing: CGFloat
        var startOffset: CGFloat = 0

        init(parent: HorizontalDragView) {
            self.parent = parent
            self.range = parent.range
            self.tickSpacing = parent.tickSpacing
        }

        // Only recognize horizontal gestures — let vertical pass to ScrollView
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let vel = pan.velocity(in: pan.view)
            return abs(vel.x) > abs(vel.y)
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                startOffset = parent.pixelOffset
            case .changed:
                let tx = pan.translation(in: pan.view).x
                let newOffset = startOffset + tx
                // Clamp to range
                let minOffset = -CGFloat(range.upperBound - range.lowerBound) * tickSpacing
                let maxOffset: CGFloat = 0
                let clamped = min(max(newOffset, minOffset), maxOffset)
                parent.pixelOffset = clamped
                // Derive integer value from offset
                let minuteValue = range.lowerBound + Int((-clamped / tickSpacing).rounded())
                let clampedVal = min(max(minuteValue, range.lowerBound), range.upperBound)
                if clampedVal != parent.value {
                    parent.value = clampedVal
                    Haptics.selection()
                }
            case .ended, .cancelled:
                let vel = pan.velocity(in: pan.view).x
                parent.onSnap(vel)
            default: break
            }
        }
    }
}

/// A horizontal ruler-style slider with tick marks, curved edges, and haptic feedback.
/// Uses a continuous pixel offset so the ruler physically slides on snap (no teleporting).
struct RulerSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    /// Continuous pixel offset that drives the ruler position.
    /// Animated on snap so the ruler visually slides instead of jumping.
    @State private var pixelOffset: CGFloat = 0
    /// The displayed value — lags behind during snap animation for a natural feel.
    @State private var displayValue: Int = 0
    @State private var hasInitialized = false
    /// Timer for animating the display value during snap
    @State private var displayTimer: Timer?

    private let tickSpacing: CGFloat = 3.0

    /// Only render every Nth minute to keep performance sane.
    private var tickStep: Int {
        if range.count > 5000 { return 30 }
        if range.count > 1000 { return 5 }
        return 1
    }

    var body: some View {
        VStack(spacing: 6) {
            // Current value display — uses displayValue (delayed during snap)
            Text(formatQuotaTime(displayValue))
                .font(.gloucester(size: 28))
                .foregroundStyle(PigeonTheme.primaryText)
                .contentTransition(.numericText())

            // Ruler
            GeometryReader { geo in
                let centerX = geo.size.width / 2
                let offsetX = centerX + pixelOffset

                ZStack(alignment: .top) {
                    // Tick marks with curve
                    Canvas { ctx, size in
                        let center = size.width / 2
                        let maxDist = size.width / 2

                        // Only render visible range of ticks
                        let visibleMin = max(range.lowerBound, Int((-offsetX - 20) / tickSpacing))
                        let visibleMax = min(range.upperBound, Int((-offsetX + size.width + 20) / tickSpacing))
                        let startTick = max(visibleMin - (visibleMin % tickStep), range.lowerBound)

                        var minute = startTick
                        while minute <= visibleMax {
                            let x = offsetX + CGFloat(minute - range.lowerBound) * tickSpacing
                            if x > -20 && x < size.width + 20 {
                                let dist = abs(x - center)
                                let normalized = min(dist / maxDist, 1.0)
                                let curveY = normalized * normalized * 14

                                let (height, opacity) = tickMetrics(for: minute)
                                let top = size.height - height - curveY
                                let bottom = size.height - curveY

                                var path = Path()
                                path.move(to: CGPoint(x: x, y: top))
                                path.addLine(to: CGPoint(x: x, y: bottom))
                                ctx.stroke(path, with: .color(PigeonTheme.primaryText.opacity(opacity)), lineWidth: 1)
                            }
                            minute += tickStep
                        }
                    }
                    .frame(height: 50)

                    // Hour labels — only visible ones
                    let labelStep = range.count > 5000 ? 120 : 60
                    let vLabelMin = max(range.lowerBound, Int((-offsetX - 40) / tickSpacing))
                    let vLabelMax = min(range.upperBound, Int((-offsetX + geo.size.width + 40) / tickSpacing))
                    let startLabel = vLabelMin - (vLabelMin % labelStep) + labelStep

                    ForEach(Array(stride(from: max(startLabel, range.lowerBound), through: vLabelMax, by: labelStep)), id: \.self) { minute in
                        let labelX = offsetX + CGFloat(minute - range.lowerBound) * tickSpacing
                        Text(formatQuotaTime(minute))
                            .font(.gloucester(size: 9))
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .position(x: labelX, y: 56)
                    }

                    // Center indicator line
                    Rectangle()
                        .fill(quotaGreen)
                        .frame(width: 2, height: 50)
                        .position(x: centerX, y: 25)

                    // Invisible UIKit pan gesture layer — only recognizes horizontal
                    HorizontalDragView(
                        value: $value,
                        pixelOffset: $pixelOffset,
                        range: range,
                        tickSpacing: tickSpacing,
                        onSnap: { velocity in
                            let speed = abs(velocity)
                            guard speed > 30 else {
                                // Even without snap, sync display
                                displayValue = value
                                return
                            }
                            let snapUnit = speed > 2000 ? 15 : speed > 1000 ? 10 : 5
                            let half = snapUnit / 2
                            let snapped = ((value + half) / snapUnit) * snapUnit
                            let momentumTicks = Int(-velocity / tickSpacing * 0.12)
                            let target = snapped + momentumTicks
                            let snapTarget = ((target + half) / snapUnit) * snapUnit
                            let clamped = min(max(snapTarget, range.lowerBound), range.upperBound)
                            if clamped != value {
                                let targetOffset = -CGFloat(clamped - range.lowerBound) * tickSpacing
                                // Delay before gliding — makes it feel natural
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    // Physically animate the ruler offset
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        pixelOffset = targetOffset
                                    }
                                    // Animate the display number partway through
                                    animateDisplayValue(from: value, to: clamped, duration: 0.45)
                                    // Set actual value at animation end
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        value = clamped
                                        displayValue = clamped
                                    }
                                    Haptics.selection()
                                }
                            } else {
                                displayValue = value
                            }
                        }
                    )
                    .frame(height: 65)
                }
                .frame(height: 65)
            }
            .frame(height: 65)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .padding(.vertical, 8)
        .onAppear {
            if !hasInitialized {
                pixelOffset = -CGFloat(value - range.lowerBound) * tickSpacing
                displayValue = value
                hasInitialized = true
            }
        }
        .onChange(of: value) { _, newVal in
            // During drag (no animation), keep display and offset in sync
            displayValue = newVal
            let expected = -CGFloat(newVal - range.lowerBound) * tickSpacing
            // Only sync if not currently animating (within 2 ticks means user is dragging)
            if abs(pixelOffset - expected) < tickSpacing * 2 {
                pixelOffset = expected
            }
        }
    }

    /// Animate the displayed number from→to over duration, stepping through intermediate values.
    private func animateDisplayValue(from: Int, to: Int, duration: Double) {
        displayTimer?.invalidate()
        let steps = max(abs(to - from) / 5, 1) // step by 5 min
        let totalSteps = min(steps, 20) // cap at 20 updates
        let interval = duration / Double(totalSteps)
        var currentStep = 0
        displayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            currentStep += 1
            let progress = Double(currentStep) / Double(totalSteps)
            let eased = progress * progress * (3 - 2 * progress) // smoothstep
            let current = from + Int(Double(to - from) * eased)
            displayValue = current
            if currentStep >= totalSteps {
                timer.invalidate()
                displayValue = to
            }
        }
    }

    private func tickMetrics(for minute: Int) -> (height: CGFloat, opacity: Double) {
        if minute % 60 == 0 { return (36, 0.7) }
        if minute % 30 == 0 { return (26, 0.5) }
        if minute % 15 == 0 { return (20, 0.4) }
        if minute % 5 == 0 { return (14, 0.3) }
        return (8, 0.15)
    }
}

// MARK: - Frequency Chip

struct FrequencyChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Text(label)
                .font(.gloucester(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? quotaGreen.opacity(0.15) : PigeonTheme.cardBackground)
                .foregroundStyle(isSelected ? quotaGreen : PigeonTheme.primaryText)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isSelected ? quotaGreen : Color.clear, lineWidth: 1)
                )
        }
    }
}

// MARK: - Shared Quota Form

/// Reusable form content for both Add and Edit views.
struct QuotaFormContent: View {
    let subjects: [StudySubject]
    @Binding var minutes: Int
    @Binding var selectedSubject: String?
    @Binding var frequency: QuotaFrequency
    @Binding var scheduledDays: Set<Weekday>
    @Binding var deadline: Date
    @State private var showMoreFrequencies = false
    @State private var useManualDateEntry = false

    /// Unified range: 5 min to 128 hours (7680 min) for all frequencies.
    private let rulerRange: ClosedRange<Int> = 5...7680

    private var targetLabel: String {
        switch frequency {
        case .daily: "Daily Target"
        case .weekly: "Weekly Target"
        case .monthly: "Monthly Target"
        case .yearly: "Yearly Target"
        case .scheduled: "Per-Day Target"
        case .oneTime: "Total Goal"
        }
    }

    private static let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Frequency
            VStack(alignment: .leading, spacing: 10) {
                Text("Frequency")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)

                // Primary row: Daily, Weekly, Monthly, One-Time
                FlowLayout(spacing: 8) {
                    FrequencyChip(label: "Daily", isSelected: frequency == .daily) { frequency = .daily }
                    FrequencyChip(label: "Weekly", isSelected: frequency == .weekly) { frequency = .weekly }
                    FrequencyChip(label: "Monthly", isSelected: frequency == .monthly) { frequency = .monthly }
                    FrequencyChip(label: "One-Time Goal", isSelected: frequency == .oneTime) { frequency = .oneTime }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showMoreFrequencies.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("More")
                                .font(.gloucester(size: 12))
                            Image(systemName: showMoreFrequencies ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .background(PigeonTheme.cardBackground)
                        .cornerRadius(20)
                    }
                }

                if showMoreFrequencies {
                    HStack(spacing: 8) {
                        FrequencyChip(label: "Yearly", isSelected: frequency == .yearly) { frequency = .yearly }
                        FrequencyChip(label: "Custom Days", isSelected: frequency == .scheduled) { frequency = .scheduled }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Scheduled: day selector
                if frequency == .scheduled {
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                Haptics.selection()
                                if scheduledDays.contains(day) { scheduledDays.remove(day) }
                                else { scheduledDays.insert(day) }
                            } label: {
                                Text(day.shortName)
                                    .font(.gloucester(size: 11))
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(scheduledDays.contains(day) ? .white : PigeonTheme.primaryText)
                                    .background(scheduledDays.contains(day) ? quotaGreen : PigeonTheme.cardBackground)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .transition(.opacity)
                }

                // One-time: deadline with calendar grid (default) or manual entry
                if frequency == .oneTime {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Deadline")
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { useManualDateEntry.toggle() }
                            } label: {
                                Text(useManualDateEntry ? "Calendar" : "Manual")
                                    .font(.gloucester(size: 11))
                                    .foregroundStyle(PigeonTheme.secondaryText)
                            }
                        }

                        if useManualDateEntry {
                            manualDeadlinePicker
                        } else {
                            calendarGrid
                        }
                    }
                    .transition(.opacity)
                }
            }

            // Target ruler — same for all frequencies
            VStack(alignment: .leading, spacing: 4) {
                Text(targetLabel)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)

                RulerSlider(value: $minutes, range: rulerRange)
            }

            // Subject picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Subject")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)

                FlowLayout(spacing: 8) {
                    ForEach(subjects) { subject in
                        Button {
                            Haptics.selection()
                            selectedSubject = subject.name
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(subject.color)
                                    .frame(width: 8, height: 8)
                                Text(subject.name)
                                    .font(.gloucester(size: 12))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedSubject == subject.name
                                         ? quotaGreen.opacity(0.15)
                                         : PigeonTheme.cardBackground)
                            .foregroundStyle(selectedSubject == subject.name
                                             ? quotaGreen
                                             : PigeonTheme.primaryText)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(selectedSubject == subject.name
                                                  ? quotaGreen
                                                  : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Deadline Helpers

    private var cal: Calendar { Calendar.current }

    private var deadlineMonth: Int { cal.component(.month, from: deadline) }
    private var deadlineDay: Int { cal.component(.day, from: deadline) }
    private var deadlineYear: Int { cal.component(.year, from: deadline) }

    private func setDeadline(month: Int, day: Int, year: Int) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        if let date = cal.date(from: comps), date >= cal.startOfDay(for: Date()) {
            deadline = date
        }
    }

    /// Format year without commas (e.g. "2026" not "2,026")
    private func yearString(_ y: Int) -> String {
        "\(y)"
    }

    // MARK: - Calendar Grid (default)

    @State private var calendarDisplayMonth: Date = Date()

    private var calendarGrid: some View {
        let today = cal.startOfDay(for: Date())
        let displayComps = cal.dateComponents([.year, .month], from: calendarDisplayMonth)
        let firstOfMonth = cal.date(from: displayComps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun
        let leadingBlanks = firstWeekday - 1

        return VStack(spacing: 8) {
            // Month/Year nav
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        calendarDisplayMonth = cal.date(byAdding: .month, value: -1, to: calendarDisplayMonth) ?? calendarDisplayMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                }

                Spacer()

                Text("\(Self.months[displayComps.month! - 1]) \(yearString(displayComps.year!))")
                    .font(.gloucester(size: 14))
                    .foregroundStyle(PigeonTheme.primaryText)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        calendarDisplayMonth = cal.date(byAdding: .month, value: 1, to: calendarDisplayMonth) ?? calendarDisplayMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
            }
            .padding(.horizontal, 4)

            // Day-of-week header
            let dayHeaders = ["S","M","T","W","T","F","S"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(dayHeaders.indices, id: \.self) { i in
                    Text(dayHeaders[i])
                        .font(.gloucester(size: 10))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }

                // Leading blanks
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Text("")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }

                // Days
                ForEach(1...daysInMonth, id: \.self) { day in
                    let comps = DateComponents(year: displayComps.year, month: displayComps.month, day: day)
                    let date = cal.date(from: comps)!
                    let dayStart = cal.startOfDay(for: date)
                    let isPast = dayStart < today
                    let isSelected = cal.isDate(deadline, inSameDayAs: date)
                    let isToday = cal.isDate(date, inSameDayAs: Date())

                    Button {
                        guard !isPast else { return }
                        Haptics.selection()
                        deadline = date
                    } label: {
                        Text("\(day)")
                            .font(.gloucester(size: 12))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(
                                isPast ? PigeonTheme.secondaryText.opacity(0.4) :
                                isSelected ? .white :
                                isToday ? quotaGreen :
                                PigeonTheme.primaryText
                            )
                            .background(
                                isSelected ? quotaGreen :
                                isToday ? quotaGreen.opacity(0.1) :
                                Color.clear
                            )
                            .clipShape(Circle())
                    }
                    .disabled(isPast)
                }
            }
        }
        .padding(12)
        .background(PigeonTheme.cardBackground)
        .cornerRadius(12)
        .onAppear {
            calendarDisplayMonth = deadline
        }
    }

    // MARK: - Manual Date Entry (fallback)

    private var manualDeadlinePicker: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(1...12, id: \.self) { m in
                    Button(Self.months[m - 1]) {
                        Haptics.selection()
                        setDeadline(month: m, day: deadlineDay, year: deadlineYear)
                    }
                }
            } label: {
                pickerLabel(Self.months[deadlineMonth - 1])
            }

            Menu {
                let daysInMonth = cal.range(of: .day, in: .month, for: deadline)?.count ?? 31
                ForEach(1...daysInMonth, id: \.self) { d in
                    Button("\(d)") {
                        Haptics.selection()
                        setDeadline(month: deadlineMonth, day: d, year: deadlineYear)
                    }
                }
            } label: {
                pickerLabel("\(deadlineDay)")
            }

            Menu {
                let currentYear = cal.component(.year, from: Date())
                ForEach(currentYear...(currentYear + 5), id: \.self) { y in
                    Button(yearString(y)) {
                        Haptics.selection()
                        setDeadline(month: deadlineMonth, day: deadlineDay, year: y)
                    }
                }
            } label: {
                pickerLabel(yearString(deadlineYear))
            }
        }
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.gloucester(size: 14))
                .foregroundStyle(PigeonTheme.primaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(PigeonTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PigeonTheme.cardBackground)
        .cornerRadius(10)
    }

}

// MARK: - Add Quota

struct AddQuotaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var user: UserProfile
    let subjects: [StudySubject]

    @State private var selectedSubject: String? = nil
    @State private var minutes: Int = 60
    @State private var frequency: QuotaFrequency = .daily
    @State private var scheduledDays: Set<Weekday> = []
    @State private var deadline: Date = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                QuotaFormContent(
                    subjects: subjects,
                    minutes: $minutes,
                    selectedSubject: $selectedSubject,
                    frequency: $frequency,
                    scheduledDays: $scheduledDays,
                    deadline: $deadline
                )
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .pigeonWallpaper()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add Quota")
                        .font(.gloucester(size: 16))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.gloucester(size: 14))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let name = selectedSubject else { return }
                        var quotas = user.studyQuotas
                        quotas.append(StudyQuota(
                            subjectName: name,
                            targetMinutes: minutes,
                            frequency: frequency,
                            scheduledDays: frequency == .scheduled ? scheduledDays.sorted(by: { $0.rawValue < $1.rawValue }) : nil,
                            deadline: frequency == .oneTime ? deadline : nil
                        ))
                        user.studyQuotas = quotas
                        try? modelContext.save()
                        Task {
                            await SupabaseService.shared.saveDailyQuotas(user.dailyQuotasJSON, forUser: user.firebaseUID ?? "")
                        }
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.gloucester(size: 14))
                            .foregroundStyle(selectedSubject == nil ? PigeonTheme.secondaryText : PigeonTheme.primaryText)
                    }
                    .disabled(selectedSubject == nil)
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Edit Quota

struct EditQuotaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var user: UserProfile
    let quota: StudyQuota
    let subjects: [StudySubject]

    @State private var selectedSubject: String? = nil
    @State private var minutes: Int = 60
    @State private var frequency: QuotaFrequency = .daily
    @State private var scheduledDays: Set<Weekday> = []
    @State private var deadline: Date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                QuotaFormContent(
                    subjects: subjects,
                    minutes: $minutes,
                    selectedSubject: $selectedSubject,
                    frequency: $frequency,
                    scheduledDays: $scheduledDays,
                    deadline: $deadline
                )
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .pigeonWallpaper()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Quota")
                        .font(.gloucester(size: 16))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.gloucester(size: 14))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        var quotas = user.studyQuotas
                        if let idx = quotas.firstIndex(where: { $0.id == quota.id }) {
                            quotas[idx].subjectName = selectedSubject ?? quota.subjectName
                            quotas[idx].targetMinutes = minutes
                            quotas[idx].frequency = frequency
                            quotas[idx].scheduledDays = frequency == .scheduled ? scheduledDays.sorted(by: { $0.rawValue < $1.rawValue }) : nil
                            quotas[idx].deadline = frequency == .oneTime ? deadline : nil
                        }
                        user.studyQuotas = quotas
                        try? modelContext.save()
                        Task {
                            await SupabaseService.shared.saveDailyQuotas(user.dailyQuotasJSON, forUser: user.firebaseUID ?? "")
                        }
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.gloucester(size: 14))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
            }
            .onAppear {
                selectedSubject = quota.subjectName
                minutes = quota.targetMinutes
                frequency = quota.frequency
                scheduledDays = Set(quota.scheduledDays ?? [])
                deadline = quota.deadline ?? Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
}
