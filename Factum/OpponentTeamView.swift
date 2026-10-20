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
    @State private var rosterSlots: [RosterSlotRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var managerRating: ManagerRatingRow?
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

                    let active = rosterSlots.filter { $0.isActive }
                    let bench = rosterSlots.filter { !$0.isActive }

                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("STARTERS")
                                    .pigeonSectionTitle()
                                Spacer()
                                Text("\(active.count)")
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }

                            // Column header
                            HStack(spacing: 0) {
                                Text("PLAYER")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("WK PTS")
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)

                            ForEach(Array(active.enumerated()), id: \.element.id) { index, slot in
                                opponentSlotRow(slot, slotIndex: index)
                            }
                        }
                        .staggeredAppear(index: 3, appeared: appeared)
                    }

                    if !bench.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BENCH")
                                .pigeonSectionTitle()
                            ForEach(bench, id: \.id) { slot in
                                opponentSlotRow(slot, slotIndex: nil)
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

    private func opponentSlotRow(_ slot: RosterSlotRow, slotIndex: Int?) -> some View {
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
            // Subject color bar
            RoundedRectangle(cornerRadius: 3)
                .fill(subjectColor)
                .frame(width: 5, height: 40)

            HStack(spacing: 10) {
                // Multiplier or slot number
                VStack(spacing: 1) {
                    if slot.isActive && slot.multiplier > 1 {
                        Text("\(slot.multiplier)×")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(slot.multiplier == 3 ? .orange : .blue)
                    } else if let slotIndex {
                        Text("\(slotIndex + 1)")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(subjectColor)
                            .frame(width: 6, height: 6)
                        Text(slot.subjectName)
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

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
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 12)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    // MARK: - Manager Rating Card

    @ViewBuilder
    private func managerRatingCard(_ rating: ManagerRatingRow) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("MANAGER RATING")
                    .pigeonSectionTitle()
                Spacer()
                Text(letterGrade(rating.overallRating))
                    .font(.gloucester(size: 28))
                    .foregroundStyle(gradeColor(rating.overallRating))
            }

            HStack(spacing: 0) {
                ratingPill("Overall", value: rating.overallRating)
                ratingPill("Draft", value: rating.draftGrade)
                ratingPill("Trade", value: rating.tradeGrade)
                ratingPill("Roster", value: rating.rosterManagementGrade)
                ratingPill("Consist.", value: rating.consistencyGrade)
            }

            // Rating bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(PigeonTheme.separator)
                            .frame(height: 6)
                        Capsule()
                            .fill(gradeColor(rating.overallRating))
                            .frame(width: geo.size.width * CGFloat(min(rating.overallRating, 100) / 100.0), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(String(format: "%.0f / 100", rating.overallRating))
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Spacer()
                }
            }
        }
        .padding(14)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    private func ratingPill(_ label: String, value: Double) -> some View {
        VStack(spacing: 3) {
            Text(letterGrade(value))
                .font(PigeonTheme.captionFont)
                .foregroundStyle(gradeColor(value))
            Text(label)
                .font(.gloucester(size: 10))
                .foregroundStyle(PigeonTheme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rating Helpers

    private func letterGrade(_ score: Double) -> String {
        switch score {
        case 97...100: return "A+"
        case 93..<97: return "A"
        case 90..<93: return "A-"
        case 87..<90: return "B+"
        case 83..<87: return "B"
        case 80..<83: return "B-"
        case 77..<80: return "C+"
        case 73..<77: return "C"
        case 70..<73: return "C-"
        case 67..<70: return "D+"
        case 63..<67: return "D"
        case 60..<63: return "D-"
        default: return "F"
        }
    }

    private func gradeColor(_ score: Double) -> Color {
        switch score {
        case 90...100: return .green
        case 80..<90: return .blue
        case 70..<80: return .yellow
        case 60..<70: return .orange
        default: return PigeonTheme.destructive
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            let teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            team = teams.first(where: { $0.id == teamID })
            rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: teamID)
            let uids = Array(Set(rosterSlots.map { $0.playerUid }))
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: uids)
            for p in profiles { memberProfiles[p.uid.uuidString] = p }

            // Fetch manager rating for the team owner
            if let ownerUID = team?.ownerUid {
                let allRatings = try await SupabaseService.shared.fetchManagerRatings(leagueID: leagueID)
                managerRating = allRatings.first(where: { $0.managerUid == ownerUID })
            }
        } catch {
            print("[OPPONENT] Load failed: \(error)")
        }
        isLoading = false
    }
}
