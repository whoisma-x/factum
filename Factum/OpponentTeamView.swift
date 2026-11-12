//
//  OpponentTeamView.swift
//  Pigeon
//
//  View another team's roster and stats with subject color indicators
//

import SwiftUI
import SwiftData

struct OpponentTeamView: View {
    let teamID: UUID
    let leagueID: UUID
    @Query private var localTimelapses: [StudyTimelapse]
    @Query private var subjects: [StudySubject]

    @State private var league: FantasyLeagueRow?
    @State private var team: FantasyTeamRow?
    @State private var allTeams: [FantasyTeamRow] = []
    @State private var rosterSlots: [RosterSlotRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var managerRating: ManagerRatingRow?
    @State private var matchupHistory: [WeeklyMatchupRow] = []
    @State private var isLoading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

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
                    Text(team?.teamName ?? "Team")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    if let team {
                        Text("\(team.wins)-\(team.losses)")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    if let team {
                        PigeonStatRow(stats: [
                            (value: "\(team.wins)-\(team.losses)", label: "Record"),
                            (value: String(format: "%.0f", team.totalPointsFor), label: "Points For"),
                            (value: String(format: "%.0f", team.totalPointsAgainst), label: "Points Against"),
                        ])
                        .staggeredAppear(index: 1, appeared: appeared)
                    }

                    // Manager Rating
                    if let rating = managerRating {
                        managerRatingCard(rating)
                            .staggeredAppear(index: 2, appeared: appeared)
                    }

                    // Recent Results
                    if !matchupHistory.isEmpty {
                        recentResultsSection
                            .staggeredAppear(index: 3, appeared: appeared)
                    }

                    let positions = (league?.slotMultipliers ?? []).sorted(by: >)
                    let active = rosterSlots.filter { $0.isActive }.sorted { $0.multiplier > $1.multiplier }
                    let bench = rosterSlots.filter { !$0.isActive }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("STARTERS")
                                .pigeonSectionTitle()
                            Spacer()
                            Text("\(active.count)/\(positions.count)")
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }

                        // Column header
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 34)
                            Text("PLAYER")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("WK PTS")
                                .frame(width: 56, alignment: .trailing)
                        }
                        .font(.gloucester(size: 10))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)

                        // Show fixed slot positions
                        let orderedSlots = orderedOpponentSlots(active: active, positions: positions)
                        ForEach(Array(positions.enumerated()), id: \.offset) { index, mult in
                            if let slot = orderedSlots[index] {
                                opponentSlotRow(slot, slotMultiplier: mult)
                            } else {
                                opponentEmptySlotRow(multiplier: mult)
                            }
                        }
                    }
                    .staggeredAppear(index: 3, appeared: appeared)

                    if !bench.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BENCH")
                                .pigeonSectionTitle()
                            ForEach(bench, id: \.id) { slot in
                                opponentSlotRow(slot, slotMultiplier: 1)
                            }
                        }
                        .staggeredAppear(index: 4, appeared: appeared)
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

    /// Order active slots to match slot positions, similar to MyTeamView.
    private func orderedOpponentSlots(active: [RosterSlotRow], positions: [Int]) -> [RosterSlotRow?] {
        guard !positions.isEmpty else { return [] }
        var available = active
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

    private func opponentSlotRow(_ slot: RosterSlotRow, slotMultiplier: Int) -> some View {
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
                Text(slot.subjectName)
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    private func opponentEmptySlotRow(multiplier: Int) -> some View {
        HStack(spacing: 8) {
            // Multiplier badge
            Text("\(multiplier)×")
                .font(.gloucester(size: 11))
                .foregroundStyle(multiplierColor(multiplier).opacity(0.8))
                .frame(width: 28, height: 22)
                .background(multiplierColor(multiplier).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text("(empty)")
                .font(.gloucester(size: 13))
                .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.6))
                .italic()

            Spacer()

            Text("—")
                .font(.gloucester(size: 14))
                .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.4))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .pigeonGlassSurface(cornerRadius: 12)
        .opacity(0.55)
    }

    private func multiplierColor(_ mult: Int) -> Color {
        switch mult {
        case 3: return .orange
        case 2: return .blue
        default: return PigeonTheme.secondaryText
        }
    }

    // MARK: - Recent Results

    private var recentResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT RESULTS")
                .pigeonSectionTitle()

            VStack(spacing: 0) {
                ForEach(Array(matchupHistory.prefix(5).enumerated()), id: \.element.id) { index, matchup in
                    let isTeam1 = matchup.team1Id == teamID
                    let myScore = isTeam1 ? matchup.team1Score : matchup.team2Score
                    let oppScore = isTeam1 ? matchup.team2Score : matchup.team1Score
                    let oppID = isTeam1 ? matchup.team2Id : matchup.team1Id
                    let oppName = allTeams.first(where: { $0.id == oppID })?.teamName ?? "Opponent"
                    let won = matchup.winnerTeamId == teamID
                    let isFinalized = matchup.winnerTeamId != nil

                    HStack(spacing: 10) {
                        Text("W\(matchup.weekNumber)")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .frame(width: 28, alignment: .leading)

                        if matchup.isBye {
                            Text("BYE")
                                .font(.gloucester(size: 11))
                                .foregroundStyle(.orange)
                        } else if isFinalized {
                            Text(won ? "W" : "L")
                                .font(.gloucester(size: 13))
                                .foregroundStyle(won ? .green : PigeonTheme.destructive)
                                .fontWeight(.bold)
                                .frame(width: 16)
                        } else {
                            Text("-")
                                .font(.gloucester(size: 13))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .frame(width: 16)
                        }

                        Text(matchup.isBye ? "Bye Week" : "vs \(oppName)")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .lineLimit(1)

                        Spacer()

                        if !matchup.isBye {
                            Text(String(format: "%.0f-%.0f", myScore, oppScore))
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)

                    if index < min(matchupHistory.count, 5) - 1 {
                        Divider().overlay(PigeonTheme.separator).padding(.leading, 14)
                    }
                }
            }
            .pigeonGlassSurface(cornerRadius: 14)
        }
    }

    // MARK: - Manager Rating Card

    @ViewBuilder
    private func managerRatingCard(_ rating: ManagerRatingRow) -> some View {
        HStack(spacing: 14) {
            Text("MANAGER RATING")
                .pigeonSectionTitle()
            Spacer()
            Text(String(format: "%.0f", rating.overallRating))
                .font(.gloucester(size: 28))
                .foregroundStyle(ratingColor(rating.overallRating))
        }
        .padding(14)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    // MARK: - Rating Helpers

    private func ratingColor(_ rating: Double) -> Color {
        switch rating {
        case 700...: return .green
        case 550..<700: return .blue
        case 450..<550: return PigeonTheme.primaryText
        case 350..<450: return .orange
        default: return PigeonTheme.destructive
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            let fetchedTeams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            allTeams = fetchedTeams
            team = fetchedTeams.first(where: { $0.id == teamID })
            rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: teamID)
            let uids = Array(Set(rosterSlots.map { $0.playerUid }))
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: uids)
            for p in profiles { memberProfiles[p.uid.uuidString] = p }

            // Fetch manager rating for the team owner
            if let ownerUID = team?.ownerUid {
                let allRatings = try await SupabaseService.shared.fetchManagerRatings(leagueID: leagueID)
                managerRating = allRatings.first(where: { $0.managerUid == ownerUID })
            }

            // Fetch matchup history (all matchups involving this team, sorted by week desc)
            let allMatchups = try await SupabaseService.shared.fetchMatchups(leagueID: leagueID)
            matchupHistory = allMatchups
                .filter { $0.team1Id == teamID || $0.team2Id == teamID }
                .sorted { $0.weekNumber > $1.weekNumber }
        } catch {
            print("[OPPONENT] Load failed: \(error)")
        }
        isLoading = false
    }
}
