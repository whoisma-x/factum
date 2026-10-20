//
//  MyTeamView.swift
//  Pigeon
//
//  Roster management — active lineup and bench with subject color indicators
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

    private let uid = AuthService.shared.currentUserID

    private var activeSlots: [RosterSlotRow] {
        rosterSlots.filter { $0.isActive }.sorted { $0.acquiredDate < $1.acquiredDate }
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

                    // Active Roster
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("STARTERS")
                                .pigeonSectionTitle()
                            Spacer()
                            Text("\(activeSlots.count)/\(league?.maxRosterSize ?? 0)")
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }

                        if activeSlots.isEmpty {
                            Text("No players on active roster")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .padding(.vertical, 20)
                        } else {
                            // Column header
                            rosterHeader
                            ForEach(Array(activeSlots.enumerated()), id: \.element.id) { index, slot in
                                playerRow(slot, slotIndex: index, canBench: true)
                                    .staggeredAppear(index: index + 2, appeared: appeared)
                            }
                        }
                    }

                    // Bench
                    if (league?.benchSize ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("BENCH")
                                    .pigeonSectionTitle()
                                Spacer()
                                Text("\(benchSlots.count)/\(league?.benchSize ?? 0)")
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }

                            if benchSlots.isEmpty {
                                Text("Bench is empty")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(benchSlots, id: \.id) { slot in
                                    playerRow(slot, slotIndex: nil, canBench: false)
                                }
                            }
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

    // MARK: - Roster Header

    private var rosterHeader: some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("WK PTS")
                .frame(width: 56, alignment: .trailing)
            // Spacer for bench/activate button
            Color.clear.frame(width: 36)
        }
        .font(.gloucester(size: 11))
        .foregroundStyle(PigeonTheme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: - Player Row

    private func playerRow(_ slot: RosterSlotRow, slotIndex: Int?, canBench: Bool) -> some View {
        let (weekStart, weekEnd) = LeagueScoringEngine.weekBounds(for: Date())
        let config = ScoringConfig.from(json: league?.scoringConfigJson)
        let result = LeagueScoringEngine.calculateScore(
            playerUID: slot.playerUid,
            subject: slot.subjectName,
            timelapses: localTimelapses,
            weekStart: weekStart,
            weekEnd: weekEnd,
            config: config,
            multiplier: slot.multiplier
        )
        let subjectColor = StudySubject.color(for: slot.subjectName, in: subjects)

        return HStack(spacing: 0) {
            // Subject color bar — the "jersey" indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(subjectColor)
                .frame(width: 5, height: 42)

            HStack(spacing: 10) {
                // Multiplier + slot number
                VStack(spacing: 1) {
                    if slot.isActive && slot.multiplier > 1 {
                        Text("\(slot.multiplier)×")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(multiplierColor(slot.multiplier))
                    } else if let slotIndex {
                        Text("\(slotIndex + 1)")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(width: 22)

                // Player info
                VStack(alignment: .leading, spacing: 2) {
                    Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        // Subject name with color dot
                        HStack(spacing: 4) {
                            Circle()
                                .fill(subjectColor)
                                .frame(width: 7, height: 7)
                            Text(slot.subjectName)
                                .lineLimit(1)
                        }
                        Text("·")
                        Label("\(result.sessionCount)", systemImage: "book.fill")
                        Text("·")
                        Label(String(format: "%.0fm", result.totalStudyMinutes), systemImage: "clock")
                    }
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                }

                Spacer(minLength: 4)

                // Score
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", result.multipliedScore))
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    if slot.isActive && slot.multiplier > 1 {
                        Text("\(slot.multiplier)× · \(String(format: "%.1f", result.finalScore)) base")
                            .font(.gloucester(size: 10))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(width: 56, alignment: .trailing)

                // Bench/Activate button
                Button {
                    Haptics.light()
                    Task { await toggleSlot(slot) }
                } label: {
                    Image(systemName: canBench ? "arrow.down.square" : "arrow.up.square")
                        .font(.system(size: 18))
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                .frame(width: 36)
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 8)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    private func multiplierColor(_ mult: Int) -> Color {
        switch mult {
        case 3: return .orange
        case 2: return .blue
        default: return PigeonTheme.secondaryText
        }
    }

    private func toggleSlot(_ slot: RosterSlotRow) async {
        let newActive = !slot.isActive

        if newActive {
            let currentActive = rosterSlots.filter { $0.isActive }.count
            guard currentActive < (league?.maxRosterSize ?? 8) else {
                Haptics.warning()
                return
            }
        }

        do {
            try await SupabaseService.shared.toggleRosterSlotActive(slotID: slot.id, isActive: newActive)
            if let idx = rosterSlots.firstIndex(where: { $0.id == slot.id }) {
                rosterSlots[idx].isActive = newActive
            }
            Haptics.success()
        } catch {
            print("[LEAGUE] Toggle slot failed: \(error)")
            Haptics.error()
        }
    }

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
