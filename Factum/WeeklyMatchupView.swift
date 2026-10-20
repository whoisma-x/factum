//
//  WeeklyMatchupView.swift
//  Pigeon
//
//  Head-to-head matchup — scoreboard header with side-by-side roster comparison
//

import SwiftUI
import SwiftData

struct WeeklyMatchupView: View {
    let matchup: WeeklyMatchupRow
    let leagueID: UUID
    @Query private var localTimelapses: [StudyTimelapse]
    @Query private var subjects: [StudySubject]

    @State private var league: FantasyLeagueRow?
    @State private var team1: FantasyTeamRow?
    @State private var team2: FantasyTeamRow?
    @State private var team1Slots: [RosterSlotRow] = []
    @State private var team2Slots: [RosterSlotRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    private var score1: Double { teamScore(team1Slots) }
    private var score2: Double { teamScore(team2Slots) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Week \(matchup.weekNumber)")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    if matchup.isBye {
                        Text("BYE")
                            .font(.gloucester(size: 12))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    // Scoreboard
                    scoreboard
                        .staggeredAppear(index: 1, appeared: appeared)

                    // Head-to-head roster comparison
                    rosterComparison
                        .staggeredAppear(index: 2, appeared: appeared)
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

    // MARK: - Scoreboard

    private var scoreboard: some View {
        VStack(spacing: 0) {
            // Score row
            HStack(spacing: 0) {
                // Team 1
                VStack(spacing: 4) {
                    Text(team1?.teamName ?? "Team 1")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Text(String(format: "%.1f", score1))
                        .font(.gloucester(size: 40))
                        .foregroundStyle(score1 >= score2 ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                    if let t1 = team1 {
                        Text("\(t1.wins)-\(t1.losses)")
                            .font(.gloucester(size: 12))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                // VS divider
                VStack(spacing: 4) {
                    Text("VS")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(width: 40)

                // Team 2
                VStack(spacing: 4) {
                    Text(team2?.teamName ?? "Team 2")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Text(String(format: "%.1f", score2))
                        .font(.gloucester(size: 40))
                        .foregroundStyle(score2 >= score1 ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                    if let t2 = team2 {
                        Text("\(t2.wins)-\(t2.losses)")
                            .font(.gloucester(size: 12))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .pigeonGlassSurface(cornerRadius: 16)
    }

    // MARK: - Roster Comparison

    private var rosterComparison: some View {
        let active1 = team1Slots.filter { $0.isActive }
        let active2 = team2Slots.filter { $0.isActive }
        let maxSlots = max(active1.count, active2.count)

        return VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text(team1?.teamName ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PTS")
                    .frame(width: 42, alignment: .trailing)
                Rectangle()
                    .fill(PigeonTheme.separator)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 6)
                Text("PTS")
                    .frame(width: 42, alignment: .leading)
                Text(team2?.teamName ?? "")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.gloucester(size: 11))
            .foregroundStyle(PigeonTheme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(PigeonTheme.separator)

            ForEach(0..<maxSlots, id: \.self) { i in
                HStack(spacing: 0) {
                    // Team 1 player
                    if i < active1.count {
                        slotCell(active1[i], alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.1f", slotScore(active1[i])))
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 42, alignment: .trailing)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                        Text("—")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .frame(width: 42, alignment: .trailing)
                    }

                    // Center divider
                    Rectangle()
                        .fill(PigeonTheme.separator)
                        .frame(width: 1, height: 36)
                        .padding(.horizontal, 6)

                    // Team 2 player
                    if i < active2.count {
                        Text(String(format: "%.1f", slotScore(active2[i])))
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 42, alignment: .leading)
                        slotCell(active2[i], alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("—")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .frame(width: 42, alignment: .leading)
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if i < maxSlots - 1 {
                    Divider().overlay(PigeonTheme.separator).padding(.horizontal, 12)
                }
            }
        }
        .pigeonGlassSurface(cornerRadius: 14)
    }

    // MARK: - Slot Cell

    private func slotCell(_ slot: RosterSlotRow, alignment: HorizontalAlignment) -> some View {
        let subjectColor = StudySubject.color(for: slot.subjectName, in: subjects)
        let isLeading = alignment == .leading

        return HStack(spacing: 6) {
            if isLeading {
                // Color bar on left
                RoundedRectangle(cornerRadius: 2)
                    .fill(subjectColor)
                    .frame(width: 4, height: 28)
            }

            VStack(alignment: isLeading ? .leading : .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    if !isLeading && slot.multiplier > 1 {
                        multiplierBadge(slot.multiplier)
                    }
                    Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                        .font(.gloucester(size: 12))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    if isLeading && slot.multiplier > 1 {
                        multiplierBadge(slot.multiplier)
                    }
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(subjectColor)
                        .frame(width: 6, height: 6)
                    Text(slot.subjectName)
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .lineLimit(1)
                }
            }

            if !isLeading {
                // Color bar on right
                RoundedRectangle(cornerRadius: 2)
                    .fill(subjectColor)
                    .frame(width: 4, height: 28)
            }
        }
    }

    private func multiplierBadge(_ mult: Int) -> some View {
        Text("\(mult)×")
            .font(.gloucester(size: 10))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(mult == 3 ? .orange : .blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Scoring

    private func slotScore(_ slot: RosterSlotRow) -> Double {
        let config = ScoringConfig.from(json: league?.scoringConfigJson)
        return LeagueScoringEngine.calculateScore(
            playerUID: slot.playerUid,
            subject: slot.subjectName,
            timelapses: localTimelapses,
            weekStart: matchup.weekStartDate,
            weekEnd: matchup.weekEndDate,
            config: config,
            multiplier: slot.multiplier
        ).multipliedScore
    }

    private func teamScore(_ slots: [RosterSlotRow]) -> Double {
        slots.filter { $0.isActive }.reduce(0) { $0 + slotScore($1) }
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            let teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            team1 = teams.first(where: { $0.id == matchup.team1Id })
            team2 = teams.first(where: { $0.id == matchup.team2Id })

            if let t1 = team1 { team1Slots = try await SupabaseService.shared.fetchRosterSlots(teamID: t1.id) }
            if let t2 = team2 { team2Slots = try await SupabaseService.shared.fetchRosterSlots(teamID: t2.id) }

            let allUIDs = Set((team1Slots + team2Slots).map { $0.playerUid })
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: Array(allUIDs))
            for p in profiles { memberProfiles[p.uid.uuidString] = p }
        } catch {
            print("[MATCHUP] Load failed: \(error)")
        }
        isLoading = false
    }
}
