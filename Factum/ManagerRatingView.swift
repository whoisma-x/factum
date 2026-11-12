//
//  ManagerRatingView.swift
//  Pigeon
//
//  Manager ratings — chess-style numeric rating (base 500)
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

                // League Rankings (with inline expansion)
                leagueRankings
                    .staggeredAppear(index: 2, appeared: appeared)
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Rating")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("chess-style elo")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
            Spacer()
            Text(String(format: "%.0f", rating.overallRating))
                .font(.gloucester(size: 44))
                .foregroundStyle(ratingColor(rating.overallRating))
        }
        .padding(PigeonTheme.spacing16)
        .pigeonGlassSurface()
    }

    // MARK: - League Rankings

    private var leagueRankings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("League Rankings")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)
                .padding(.bottom, 12)

            let sorted = ratings.sorted { $0.overallRating > $1.overallRating }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, rating in
                let isSelected = selectedManagerUID == rating.managerUid

                VStack(spacing: 0) {
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

                    // Inline expansion directly below the tapped row
                    if isSelected {
                        managerDetail(rating)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if index < sorted.count - 1 {
                    Divider()
                        .overlay(PigeonTheme.separator)
                        .padding(.leading, 42)
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
                .foregroundStyle(rank <= 3 ? ratingColor(rating.overallRating) : PigeonTheme.tertiaryText)
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
                    .foregroundStyle(PigeonTheme.primaryText)
                    .fontWeight(isMe ? .semibold : .regular)
                if let team {
                    Text(team.teamName)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }

            Spacer()

            // Numeric rating
            Text(String(format: "%.0f", rating.overallRating))
                .font(.gloucester(size: 20))
                .foregroundStyle(ratingColor(rating.overallRating))

            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Inline Manager Detail

    @ViewBuilder
    private func managerDetail(_ rating: ManagerRatingRow) -> some View {
        let team = teams.first(where: { $0.ownerUid == rating.managerUid })

        VStack(alignment: .leading, spacing: 8) {
            if let team {
                HStack(spacing: 0) {
                    statPill(value: "\(team.wins)-\(team.losses)", label: "Record")
                    statPill(value: String(format: "%.0f", team.totalPointsFor), label: "PF")
                    statPill(value: String(format: "%.0f", team.totalPointsAgainst), label: "PA")
                    statPill(value: String(format: "%.0f", rating.overallRating), label: "Rating")
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .padding(.leading, 42)
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.gloucester(size: 14))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(.gloucester(size: 10))
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
