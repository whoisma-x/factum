//
//  StandingsView.swift
//  Pigeon
//
//  League standings and playoff bracket
//

import SwiftUI

// MARK: - Playoff Bracket View

struct PlayoffBracketView: View {
    let leagueID: UUID

    @State private var matchups: [WeeklyMatchupRow] = []
    @State private var teams: [FantasyTeamRow] = []
    @State private var isLoading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    private var playoffMatchups: [WeeklyMatchupRow] {
        matchups.filter { $0.isPlayoff }.sorted { $0.weekNumber < $1.weekNumber }
    }

    private var roundGroups: [[WeeklyMatchupRow]] {
        Dictionary(grouping: playoffMatchups) { $0.weekNumber }
            .sorted { $0.key < $1.key }
            .map { $0.value }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Playoffs")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if playoffMatchups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 48))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("Playoffs haven't started yet")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(Array(roundGroups.enumerated()), id: \.offset) { roundIdx, roundMatchups in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(roundLabel(roundIdx, totalRounds: roundGroups.count))
                                .pigeonSectionTitle()

                            ForEach(roundMatchups, id: \.id) { matchup in
                                bracketMatchup(matchup)
                            }
                        }
                        .staggeredAppear(index: roundIdx + 1, appeared: appeared)
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

    private func bracketMatchup(_ matchup: WeeklyMatchupRow) -> some View {
        let team1Name = teams.first(where: { $0.id == matchup.team1Id })?.teamName ?? "TBD"
        let team2Name = teams.first(where: { $0.id == matchup.team2Id })?.teamName ?? "TBD"
        let isTeam1Winner = matchup.winnerTeamId == matchup.team1Id
        let isTeam2Winner = matchup.winnerTeamId == matchup.team2Id

        return VStack(spacing: 0) {
            HStack {
                Text(team1Name)
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(isTeam1Winner ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                    .fontWeight(isTeam1Winner ? .bold : .regular)
                Spacer()
                Text(String(format: "%.1f", matchup.team1Score))
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            .padding(12)

            Divider().overlay(PigeonTheme.separator)

            HStack {
                Text(team2Name)
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(isTeam2Winner ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                    .fontWeight(isTeam2Winner ? .bold : .regular)
                Spacer()
                Text(String(format: "%.1f", matchup.team2Score))
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            .padding(12)
        }
        .pigeonGlassSurface(cornerRadius: 12)
    }

    private func roundLabel(_ index: Int, totalRounds: Int) -> String {
        let remaining = totalRounds - index
        switch remaining {
        case 1: return "FINALS"
        case 2: return "SEMIFINALS"
        case 3: return "QUARTERFINALS"
        default: return "ROUND \(index + 1)"
        }
    }

    private func loadData() async {
        do {
            matchups = try await SupabaseService.shared.fetchMatchups(leagueID: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
        } catch {
            print("[PLAYOFFS] Load failed: \(error)")
        }
        isLoading = false
    }
}
