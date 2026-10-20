//
//  ManagerRatingView.swift
//  Pigeon
//
//  Detailed manager rating breakdown and league-wide ranking
//

import SwiftUI
import SwiftData

struct ManagerRatingView: View {
    let leagueID: UUID
    @State private var ratings: [ManagerRatingRow] = []
    @State private var teams: [FantasyTeamRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @State private var selectedManagerUID: String?

    private let uid = AuthService.shared.currentUserID

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
                    Text("Manager Ratings")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                // My Rating Card
                if let myRating = ratings.first(where: { $0.managerUid == uid }) {
                    myRatingCard(myRating)
                        .staggeredAppear(index: 1, appeared: appeared)
                }

                // League Rankings
                leagueRankings
                    .staggeredAppear(index: 2, appeared: appeared)

                // Selected Manager Detail
                if let selectedUID = selectedManagerUID,
                   let rating = ratings.first(where: { $0.managerUid == selectedUID }) {
                    managerDetail(rating)
                        .staggeredAppear(index: 3, appeared: appeared)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .pigeonWallpaper()
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadData() }
        .onAppear { withAnimation { appeared = true } }
    }

    // MARK: - My Rating Card

    @ViewBuilder
    private func myRatingCard(_ rating: ManagerRatingRow) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("My Rating")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Spacer()
                Text(letterGrade(for: rating.overallRating))
                    .font(.gloucester(size: 40))
                    .foregroundStyle(gradeColor(for: rating.overallRating))
            }

            // Overall score bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overall")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Spacer()
                    Text(String(format: "%.0f", rating.overallRating))
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ratingBar(value: rating.overallRating)
            }

            Divider().foregroundStyle(PigeonTheme.separator)

            // Component grades
            gradeRow("Draft", value: rating.draftGrade, weight: "20%")
            gradeRow("Trades", value: rating.tradeGrade, weight: "20%")
            gradeRow("Roster Mgmt", value: rating.rosterManagementGrade, weight: "30%")
            gradeRow("Consistency", value: rating.consistencyGrade, weight: "30%")
        }
        .padding(PigeonTheme.spacing16)
        .pigeonGlassSurface()
    }

    // MARK: - League Rankings

    private var leagueRankings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("League Rankings")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)

            let sorted = ratings.sorted { $0.overallRating > $1.overallRating }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, rating in
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        if selectedManagerUID == rating.managerUid {
                            selectedManagerUID = nil
                        } else {
                            selectedManagerUID = rating.managerUid
                        }
                    }
                } label: {
                    rankingRow(rating: rating, rank: index + 1)
                }
            }
        }
        .padding(PigeonTheme.spacing16)
        .pigeonGlassSurface()
    }

    @ViewBuilder
    private func rankingRow(rating: ManagerRatingRow, rank: Int) -> some View {
        let profile = memberProfiles[rating.managerUid]
        let team = teams.first(where: { $0.ownerUid == rating.managerUid })
        let isMe = rating.managerUid == uid
        let isSelected = selectedManagerUID == rating.managerUid

        HStack(spacing: 12) {
            // Rank
            Text("#\(rank)")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(rank <= 3 ? gradeColor(for: rating.overallRating) : PigeonTheme.tertiaryText)
                .frame(width: 30)

            // Avatar
            if let avatarURL = profile?.avatarUrl, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(PigeonTheme.separator)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(PigeonTheme.separator)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayName ?? "Manager")
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(isMe ? PigeonTheme.primaryText : PigeonTheme.primaryText)
                    .fontWeight(isMe ? .semibold : .regular)
                if let team {
                    Text(team.teamName)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }

            Spacer()

            // Letter grade
            Text(letterGrade(for: rating.overallRating))
                .font(.gloucester(size: 20))
                .foregroundStyle(gradeColor(for: rating.overallRating))

            // Score
            Text(String(format: "%.0f", rating.overallRating))
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)
                .frame(width: 30, alignment: .trailing)

            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Manager Detail Expansion

    @ViewBuilder
    private func managerDetail(_ rating: ManagerRatingRow) -> some View {
        let profile = memberProfiles[rating.managerUid]
        let team = teams.first(where: { $0.ownerUid == rating.managerUid })

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? "Manager")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    if let team {
                        Text("\(team.teamName) — \(team.wins)W \(team.losses)L")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(letterGrade(for: rating.overallRating))
                        .font(.gloucester(size: 32))
                        .foregroundStyle(gradeColor(for: rating.overallRating))
                    Text(String(format: "%.1f", rating.overallRating))
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }

            Divider().foregroundStyle(PigeonTheme.separator)

            // Component breakdown
            gradeDetailRow("Draft", value: rating.draftGrade, weight: "20%",
                           description: "Performance of drafted players vs league average")
            gradeDetailRow("Trades", value: rating.tradeGrade, weight: "20%",
                           description: "Net point gain/loss from completed trades")
            gradeDetailRow("Roster Management", value: rating.rosterManagementGrade, weight: "30%",
                           description: "Lineup optimization and free agent activity")
            gradeDetailRow("Consistency", value: rating.consistencyGrade, weight: "30%",
                           description: "Week-over-week performance stability")
        }
        .padding(PigeonTheme.spacing16)
        .pigeonGlassSurface()
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func gradeRow(_ label: String, value: Double, weight: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                Text(weight)
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Spacer()
                Text(letterGrade(for: value))
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(gradeColor(for: value))
                Text(String(format: "%.0f", value))
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                    .frame(width: 30, alignment: .trailing)
            }
            ratingBar(value: value)
        }
    }

    @ViewBuilder
    private func gradeDetailRow(_ label: String, value: Double, weight: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text(weight)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    Text(description)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(letterGrade(for: value))
                        .font(.gloucester(size: 18))
                        .foregroundStyle(gradeColor(for: value))
                    Text(String(format: "%.0f", value))
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
            ratingBar(value: value)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func ratingBar(value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PigeonTheme.separator)
                    .frame(height: 6)
                Capsule()
                    .fill(gradeColor(for: value))
                    .frame(width: geo.size.width * CGFloat(min(value, 100) / 100.0), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Helpers

    private func letterGrade(for score: Double) -> String {
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

    private func gradeColor(for score: Double) -> Color {
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
        defer { isLoading = false }
        do {
            ratings = try await SupabaseService.shared.fetchManagerRatings(leagueID: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)

            // Load member profiles
            let league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            if let league {
                for memberUID in league.memberUids {
                    if let profile = try? await SupabaseService.shared.fetchUserProfile(uid: memberUID) {
                        memberProfiles[memberUID] = profile
                    }
                }
            }
        } catch {
            print("[ManagerRating] Failed to load: \(error)")
        }
    }
}
