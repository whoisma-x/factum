//
//  MyTeamView.swift
//  Pigeon
//
//  Roster management — fixed multiplier slots with drag-and-drop reordering
//

import SwiftUI
import SwiftData

struct MyTeamView: View {
    let leagueID: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var localTimelapses: [StudyTimelapse]
    @Query private var subjects: [StudySubject]

    @State private var league: FantasyLeagueRow?
    @State private var myTeam: FantasyTeamRow?
    @State private var rosterSlots: [RosterSlotRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    // Drag state
    @State private var draggingSlotID: UUID?
    @State private var dragOverTarget: DragTarget?
    @State private var isSaving = false

    private let uid = AuthService.shared.currentUserID

    /// Each entry in the unified roster: either a starter slot position or a bench position.
    private enum DragTarget: Equatable {
        case starter(index: Int)   // index into slotPositions
        case bench(slotID: UUID)   // specific bench slot
    }

    /// The multiplier config for each active slot position, sorted highest-first.
    private var slotPositions: [Int] {
        (league?.slotMultipliers ?? []).sorted(by: >)
    }

    /// Active roster slots ordered to match slot positions (highest multiplier first).
    private var orderedActiveSlots: [RosterSlotRow?] {
        let mySlots = rosterSlots.filter { $0.isActive }
            .sorted { $0.multiplier > $1.multiplier }

        let positions = slotPositions
        guard !positions.isEmpty else { return [] }

        var available = mySlots
        var result: [RosterSlotRow?] = []

        for mult in positions {
            if let idx = available.firstIndex(where: { $0.multiplier == mult }) {
                result.append(available.remove(at: idx))
            } else if !available.isEmpty {
                result.append(available.removeFirst())
            } else {
                result.append(nil)
            }
        }
        return result
    }

    private var benchSlots: [RosterSlotRow] {
        rosterSlots.filter { !$0.isActive }.sorted { $0.acquiredDate < $1.acquiredDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text(myTeam?.teamName ?? "My Team")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    if let myTeam {
                        Text("\(myTeam.wins)-\(myTeam.losses)")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    // Team Stats
                    if let myTeam {
                        PigeonStatRow(stats: [
                            (value: "\(myTeam.wins)-\(myTeam.losses)", label: "Record"),
                            (value: String(format: "%.0f", myTeam.totalPointsFor), label: "Total PF"),
                            (value: "\(rosterSlots.count)", label: "Roster"),
                        ])
                        .staggeredAppear(index: 1, appeared: appeared)
                    }

                    // Starters — fixed slot positions
                    let positions = slotPositions
                    let activeSlotsList = orderedActiveSlots
                    let filledCount = activeSlotsList.compactMap({ $0 }).count

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("STARTERS")
                                .pigeonSectionTitle()
                            Spacer()
                            Text("\(filledCount)/\(positions.count)")
                                .font(.gloucester(size: 11))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }

                        rosterHeader

                        ForEach(Array(positions.enumerated()), id: \.offset) { index, mult in
                            let target = DragTarget.starter(index: index)
                            let isDropTarget = dragOverTarget == target && draggingSlotID != nil

                            if let slot = activeSlotsList[index] {
                                playerRow(slot, slotIndex: index, slotMultiplier: mult, canBench: true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isDropTarget ? multiplierColor(mult) : .clear, lineWidth: 2)
                                    )
                                    .opacity(draggingSlotID == slot.id ? 0.4 : 1.0)
                                    .scaleEffect(draggingSlotID == slot.id ? 0.95 : 1.0)
                                    .onLongPressGesture(minimumDuration: 0.3) {
                                        guard !isSaving else { return }
                                        Haptics.medium()
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            draggingSlotID = slot.id
                                        }
                                    }
                                    .onTapGesture {
                                        if let dragging = draggingSlotID, dragging != slot.id {
                                            Task { await handleDrop(draggedSlotID: dragging, onto: target) }
                                        }
                                    }
                                    .staggeredAppear(index: index + 2, appeared: appeared)
                            } else {
                                emptySlotRow(index: index, multiplier: mult)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isDropTarget ? multiplierColor(mult) : .clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        if let dragging = draggingSlotID {
                                            Task { await handleDrop(draggedSlotID: dragging, onto: target) }
                                        }
                                    }
                                    .staggeredAppear(index: index + 2, appeared: appeared)
                            }
                        }
                    }

                    // Bench — always show
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("BENCH")
                                .pigeonSectionTitle()
                            Spacer()
                            Text("\(benchSlots.count)/\(league?.benchSize ?? 2)")
                                .font(.gloucester(size: 11))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }

                        if benchSlots.isEmpty && draggingSlotID != nil {
                            // Show a drop target for benching when bench is empty
                            benchDropTarget
                        } else if benchSlots.isEmpty {
                            Text("Bench is empty")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(benchSlots, id: \.id) { slot in
                                let target = DragTarget.bench(slotID: slot.id)
                                let isDropTarget = dragOverTarget == target && draggingSlotID != nil

                                playerRow(slot, slotIndex: nil, slotMultiplier: 1, canBench: false)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isDropTarget ? PigeonTheme.secondaryText : .clear, lineWidth: 2)
                                    )
                                    .opacity(draggingSlotID == slot.id ? 0.4 : 1.0)
                                    .scaleEffect(draggingSlotID == slot.id ? 0.95 : 1.0)
                                    .onLongPressGesture(minimumDuration: 0.3) {
                                        guard !isSaving else { return }
                                        Haptics.medium()
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            draggingSlotID = slot.id
                                        }
                                    }
                                    .onTapGesture {
                                        if let dragging = draggingSlotID, dragging != slot.id {
                                            Task { await handleDrop(draggedSlotID: dragging, onto: target) }
                                        }
                                    }
                            }
                            if draggingSlotID != nil {
                                benchDropTarget
                            }
                        }
                    }

                    // Cancel drag hint
                    if draggingSlotID != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                draggingSlotID = nil
                                dragOverTarget = nil
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel move")
                            }
                            .font(.gloucester(size: 13))
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .pigeonGlassSurface(cornerRadius: 10)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .pigeonWallpaper()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { withAnimation { appeared = true } }
        .task { await loadData() }
    }

    // MARK: - Bench Drop Target

    private var benchDropTarget: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 13, weight: .medium))
            Text("Tap to bench")
                .font(.gloucester(size: 12))
        }
        .foregroundStyle(PigeonTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PigeonTheme.secondaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PigeonTheme.secondaryText.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
        )
        .onTapGesture {
            if let dragging = draggingSlotID {
                Task { await handleBench(slotID: dragging) }
            }
        }
    }

    // MARK: - Roster Header

    private var rosterHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 34) // slot badge width
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("WK PTS")
                .frame(width: 56, alignment: .trailing)
            Color.clear.frame(width: 36)
        }
        .font(.gloucester(size: 10))
        .foregroundStyle(PigeonTheme.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Empty Slot Row

    private func emptySlotRow(index: Int, multiplier: Int) -> some View {
        HStack(spacing: 8) {
            // Multiplier badge
            Text("\(multiplier)×")
                .font(.gloucester(size: 11))
                .foregroundStyle(multiplierColor(multiplier).opacity(0.8))
                .frame(width: 28, height: 22)
                .background(multiplierColor(multiplier).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(draggingSlotID != nil ? "Tap to place here" : "(empty)")
                .font(.gloucester(size: 13))
                .foregroundStyle(draggingSlotID != nil ? multiplierColor(multiplier) : PigeonTheme.tertiaryText.opacity(0.6))
                .italic()

            Spacer()

            Text("—")
                .font(.gloucester(size: 14))
                .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.4))
                .frame(width: 56, alignment: .trailing)

            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .pigeonGlassSurface(cornerRadius: 12)
        .opacity(draggingSlotID != nil ? 0.85 : 0.55)
    }

    // MARK: - Player Row

    private func playerRow(_ slot: RosterSlotRow, slotIndex: Int?, slotMultiplier: Int, canBench: Bool) -> some View {
        let (weekStart, weekEnd) = LeagueScoringEngine.weekBounds(for: Date())
        let config = ScoringConfig.from(json: league?.scoringConfigJson)
        let effectiveMultiplier = slot.isActive ? slotMultiplier : 1
        let result = LeagueScoringEngine.calculateScore(
            playerUID: slot.playerUid,
            subject: slot.subjectName,
            timelapses: localTimelapses,
            weekStart: weekStart,
            weekEnd: weekEnd,
            config: config,
            multiplier: effectiveMultiplier
        )
        let subjectColor = StudySubject.color(for: slot.subjectName, in: subjects)
        let isDragging = draggingSlotID != nil
        let isMe = draggingSlotID == slot.id

        return HStack(spacing: 8) {
            // Multiplier badge
            Text(slot.isActive ? "\(slotMultiplier)×" : "BN")
                .font(.gloucester(size: 11))
                .foregroundStyle(slot.isActive ? multiplierColor(slotMultiplier) : PigeonTheme.tertiaryText)
                .frame(width: 28, height: 22)
                .background(
                    slot.isActive
                        ? multiplierColor(slotMultiplier).opacity(0.12)
                        : PigeonTheme.tertiaryText.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))

            // Subject color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(subjectColor)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(slot.subjectName)
                        .lineLimit(1)
                    if !isDragging {
                        Text("·")
                        Text("\(result.sessionCount) ses")
                        Text("·")
                        Text(String(format: "%.0fm", result.totalStudyMinutes))
                    }
                }
                .font(.gloucester(size: 11))
                .foregroundStyle(PigeonTheme.tertiaryText)
            }

            Spacer(minLength: 4)

            if isDragging && !isMe {
                Text("Tap to swap")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PigeonTheme.secondaryText.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", result.multipliedScore))
                        .font(.gloucester(size: 16))
                        .foregroundStyle(PigeonTheme.primaryText)
                    if slot.isActive && slotMultiplier > 1 {
                        Text("\(String(format: "%.1f", result.finalScore)) base")
                            .font(.gloucester(size: 10))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(width: 56, alignment: .trailing)
            }

            if !isDragging {
                Button {
                    Haptics.light()
                    Task { await toggleSlot(slot, targetMultiplier: canBench ? 1 : nextAvailableMultiplier()) }
                } label: {
                    Image(systemName: canBench ? "arrow.down.square" : "arrow.up.square")
                        .font(.system(size: 16))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(width: 30)
            } else {
                Color.clear.frame(width: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    private func multiplierColor(_ mult: Int) -> Color {
        switch mult {
        case 3: return Color(red: 0.85, green: 0.55, blue: 0.15)
        case 2: return Color(red: 0.35, green: 0.55, blue: 0.75)
        default: return PigeonTheme.secondaryText
        }
    }

    // MARK: - Drag & Drop Handling

    /// Handle dropping a dragged slot onto a starter position (swap or move).
    private func handleDrop(draggedSlotID: UUID, onto target: DragTarget) async {
        guard !isSaving else { return }
        isSaving = true
        defer {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingSlotID = nil
                dragOverTarget = nil
            }
            isSaving = false
        }

        guard let draggedSlot = rosterSlots.first(where: { $0.id == draggedSlotID }) else { return }

        switch target {
        case .starter(let targetIndex):
            let positions = slotPositions
            guard targetIndex < positions.count else { return }
            let targetMult = positions[targetIndex]
            let activeList = orderedActiveSlots

            if let targetSlot = activeList[targetIndex] {
                // Swap: dragged slot takes the target position's multiplier, target slot takes dragged's position
                // Find what multiplier the dragged slot currently occupies
                let draggedMult = draggedSlot.multiplier
                let draggedWasActive = draggedSlot.isActive

                do {
                    // Update dragged slot → target position
                    try await SupabaseService.shared.updateRosterSlot(
                        slotID: draggedSlotID, isActive: true, multiplier: targetMult
                    )
                    // Update target slot → dragged position (or bench if dragged was bench)
                    try await SupabaseService.shared.updateRosterSlot(
                        slotID: targetSlot.id, isActive: draggedWasActive, multiplier: draggedWasActive ? draggedMult : 1
                    )
                    Haptics.success()
                    if let myTeam {
                        rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
                    }
                } catch {
                    print("[LEAGUE] Swap failed: \(error)")
                    Haptics.error()
                }
            } else {
                // Empty slot: just move the dragged player there
                do {
                    try await SupabaseService.shared.updateRosterSlot(
                        slotID: draggedSlotID, isActive: true, multiplier: targetMult
                    )
                    Haptics.success()
                    if let myTeam {
                        rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
                    }
                } catch {
                    print("[LEAGUE] Move to slot failed: \(error)")
                    Haptics.error()
                }
            }

        case .bench(let benchSlotID):
            // Swap dragged player with a bench player
            guard let benchSlot = rosterSlots.first(where: { $0.id == benchSlotID }) else { return }
            let draggedMult = draggedSlot.multiplier
            let draggedWasActive = draggedSlot.isActive

            do {
                try await SupabaseService.shared.updateRosterSlot(
                    slotID: draggedSlotID, isActive: false, multiplier: 1
                )
                try await SupabaseService.shared.updateRosterSlot(
                    slotID: benchSlotID, isActive: draggedWasActive, multiplier: draggedWasActive ? draggedMult : 1
                )
                Haptics.success()
                if let myTeam {
                    rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
                }
            } catch {
                print("[LEAGUE] Bench swap failed: \(error)")
                Haptics.error()
            }
        }
    }

    /// Bench a dragged player (no swap, just move to bench).
    private func handleBench(slotID: UUID) async {
        guard !isSaving else { return }
        isSaving = true
        defer {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingSlotID = nil
                dragOverTarget = nil
            }
            isSaving = false
        }

        do {
            try await SupabaseService.shared.updateRosterSlot(slotID: slotID, isActive: false, multiplier: 1)
            Haptics.success()
            if let myTeam {
                rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
            }
        } catch {
            print("[LEAGUE] Bench failed: \(error)")
            Haptics.error()
        }
    }

    // MARK: - Slot Management

    /// Find the highest available multiplier for the next open starter slot.
    private func nextAvailableMultiplier() -> Int {
        let positions = slotPositions
        let activeSlots = rosterSlots.filter { $0.isActive }

        var filled: [Int: Int] = [:]
        for slot in activeSlots {
            filled[slot.multiplier, default: 0] += 1
        }

        var available: [Int: Int] = [:]
        for mult in positions {
            available[mult, default: 0] += 1
        }

        for mult in positions.sorted(by: >) {
            let filledCount = filled[mult] ?? 0
            let totalCount = available[mult] ?? 0
            if filledCount < totalCount {
                return mult
            }
        }
        return 1
    }

    private func toggleSlot(_ slot: RosterSlotRow, targetMultiplier: Int) async {
        let newActive = !slot.isActive

        if newActive {
            let currentActive = rosterSlots.filter { $0.isActive }.count
            guard currentActive < (league?.maxRosterSize ?? 8) else {
                Haptics.warning()
                return
            }
        }

        let newMultiplier = newActive ? targetMultiplier : 1

        do {
            try await SupabaseService.shared.updateRosterSlot(slotID: slot.id, isActive: newActive, multiplier: newMultiplier)
            if let idx = rosterSlots.firstIndex(where: { $0.id == slot.id }) {
                rosterSlots[idx].isActive = newActive
                rosterSlots[idx].multiplier = newMultiplier
            }
            Haptics.success()
            if let myTeam {
                rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
            }
        } catch {
            print("[LEAGUE] Toggle slot failed: \(error)")
            Haptics.error()
            if let idx = rosterSlots.firstIndex(where: { $0.id == slot.id }) {
                rosterSlots[idx].isActive = !newActive
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            let teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            myTeam = teams.first(where: { $0.ownerUid == uid })

            if let myTeam {
                rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
            }

            let playerUIDs = Array(Set(rosterSlots.map { $0.playerUid }))
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: playerUIDs)
            for p in profiles {
                memberProfiles[p.uid.uuidString] = p
            }
        } catch {
            print("[LEAGUE] Team load failed: \(error)")
        }
        isLoading = false
    }
}
