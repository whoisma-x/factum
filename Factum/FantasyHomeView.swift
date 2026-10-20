//
//  FantasyHomeView.swift
//  Pigeon
//
//  Fantasy league home dashboard — clean overview of your leagues

import SwiftUI
import SwiftData

struct FantasyHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query private var localTimelapses: [StudyTimelapse]

    @State private var leagues: [FantasyLeagueRow] = []
    @State private var teams: [UUID: FantasyTeamRow] = [:]
    @State private var matchups: [UUID: WeeklyMatchupRow] = [:]
    @State private var allTeams: [UUID: [FantasyTeamRow]] = [:]
    @State private var trades: [UUID: [TradeProposalRow]] = [:]
    @State private var rosters: [UUID: [RosterSlotRow]] = [:]
    @State private var managerRatings: [UUID: ManagerRatingRow] = [:]
    @State private var memberNames: [String: String] = [:] // uid -> displayName
    @State private var invites: [(invite: LeagueInviteRow, leagueName: String)] = []
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showCreateLeague = false

    private let uid = AuthService.shared.currentUserID

    private var currentUser: UserProfile? {
        users.first { $0.firebaseUID == uid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack(spacing: 8) {
                        PigeonIcon(size: 28, color: PigeonTheme.primaryText)
                        Text("pigeon.")
                            .font(.gloucester(size: 28))
                            .foregroundStyle(PigeonTheme.primaryText)
                            .tracking(2)
                        Spacer()
                        Button {
                            Haptics.medium()
                            showCreateLeague = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                    }
                    .padding(.top, 8)
                    .staggeredAppear(index: 0, appeared: appeared)

                    if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        if !invites.isEmpty {
                            inviteBanner
                                .staggeredAppear(index: 1, appeared: appeared)
                        }

                        if leagues.isEmpty {
                            emptyState
                                .staggeredAppear(index: 2, appeared: appeared)
                        } else {
                            ForEach(Array(leagues.enumerated()), id: \.element.id) { index, league in
                                leagueSection(league)
                                    .staggeredAppear(index: index + 2, appeared: appeared)
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
            .sheet(isPresented: $showCreateLeague) {
                CreateLeagueView {
                    Task { await loadData() }
                }
            }
            .task { await loadData() }
        }
    }

    // MARK: - Per-League Section

    private func leagueSection(_ league: FantasyLeagueRow) -> some View {
        let myTeam = teams[league.id]
        let leagueTeams = allTeams[league.id] ?? []
        let currentWeek = LeagueScoringEngine.weekNumber(for: Date(), seasonStart: league.seasonStartDate)
        let pendingTrades = (trades[league.id] ?? []).filter { $0.status == "pending" }
        let myRating = managerRatings[league.id]

        return VStack(alignment: .leading, spacing: 12) {
            // League header
            NavigationLink {
                LeagueDashboardView(leagueID: league.id)
            } label: {
                HStack(spacing: 10) {
                    if league.iconName.hasPrefix("emoji:") {
                        Text(String(league.iconName.dropFirst(6)))
                            .font(.system(size: 20))
                    } else {
                        Image(systemName: league.iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }

                    Text(league.name)
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)

                    statusBadge(league.draftStatus)

                    Spacer()

                    Text("Week \(currentWeek)")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            .buttonStyle(.plain)

            if let myTeam {
                // Matchup card
                if let matchup = matchups[league.id] {
                    NavigationLink {
                        WeeklyMatchupView(matchup: matchup, leagueID: league.id)
                    } label: {
                        matchupCard(matchup, league: league, myTeam: myTeam)
                    }
                    .buttonStyle(.plain)
                }

                // Record + stats row
                recordRow(myTeam, in: leagueTeams, rating: myRating)

                // Quick actions
                quickActions(league: league, pendingTrades: pendingTrades, myTeam: myTeam)

                // Standings
                if leagueTeams.count > 1 {
                    standingsPreview(leagueTeams, myTeamID: myTeam.id, leagueID: league.id)
                }
            } else {
                preDraftCard(league)
            }
        }
        .padding(16)
        .pigeonGlassSurface(cornerRadius: 16)
    }

    // MARK: - Matchup Card

    private func matchupCard(_ matchup: WeeklyMatchupRow, league: FantasyLeagueRow, myTeam: FantasyTeamRow) -> some View {
        let leagueTeams = allTeams[league.id] ?? []
        let opponentID = matchup.team1Id == myTeam.id ? matchup.team2Id : matchup.team1Id
        let opponentName = leagueTeams.first { $0.id == opponentID }?.teamName ?? "Opponent"
        let myScore = matchup.team1Id == myTeam.id ? matchup.team1Score : matchup.team2Score
        let oppScore = matchup.team1Id == myTeam.id ? matchup.team2Score : matchup.team1Score
        let isWinning = myScore > oppScore
        let isTied = myScore == oppScore && myScore == 0

        return HStack(spacing: 0) {
            // My side
            VStack(spacing: 4) {
                Text(String(format: "%.1f", myScore))
                    .font(.gloucester(size: 32))
                    .foregroundStyle(PigeonTheme.primaryText)
                Text(myTeam.teamName)
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text("vs")
                    .font(.gloucester(size: 12))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                if !isTied {
                    Text(isWinning ? "▲" : "▼")
                        .font(.system(size: 10))
                        .foregroundStyle(isWinning ? .green : .red)
                }
            }
            .frame(width: 30)

            // Opponent side
            VStack(spacing: 4) {
                Text(String(format: "%.1f", oppScore))
                    .font(.gloucester(size: 32))
                    .foregroundStyle(PigeonTheme.secondaryText)
                Text(opponentName)
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(PigeonTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Record Row

    private func recordRow(_ myTeam: FantasyTeamRow, in leagueTeams: [FantasyTeamRow], rating: ManagerRatingRow?) -> some View {
        HStack(spacing: 0) {
            statCell(
                value: "\(myTeam.wins)-\(myTeam.losses)\(myTeam.ties > 0 ? "-\(myTeam.ties)" : "")",
                label: "Record"
            )
            statDivider
            statCell(
                value: String(format: "%.0f", myTeam.totalPointsFor),
                label: "PF"
            )
            statDivider
            statCell(
                value: rankString(myTeam, in: leagueTeams),
                label: "Rank"
            )
            if let rating {
                statDivider
                statCell(
                    value: letterGrade(rating.overallRating),
                    label: "Rating"
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.gloucester(size: 15))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(.gloucester(size: 9))
                .foregroundStyle(PigeonTheme.tertiaryText)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(PigeonTheme.separator)
            .frame(width: 1, height: 20)
    }

    // MARK: - Quick Actions

    private func quickActions(league: FantasyLeagueRow, pendingTrades: [TradeProposalRow], myTeam: FantasyTeamRow) -> some View {
        let incoming = pendingTrades.filter { $0.receiverTeamId == myTeam.id }

        return HStack(spacing: 8) {
            NavigationLink {
                TradeView(leagueID: league.id)
            } label: {
                actionButton(icon: "arrow.left.arrow.right", label: "Trades", badge: incoming.count, highlight: !incoming.isEmpty)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FreeAgentView(leagueID: league.id)
            } label: {
                actionButton(icon: "person.badge.plus", label: "Waivers")
            }
            .buttonStyle(.plain)

            NavigationLink {
                MyTeamView(leagueID: league.id)
            } label: {
                actionButton(icon: "person.3", label: "Roster")
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(icon: String, label: String, badge: Int = 0, highlight: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(PigeonTheme.smallFont)
            if badge > 0 {
                Text("\(badge)")
                    .font(.gloucester(size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.orange)
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(highlight ? .orange : PigeonTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(PigeonTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Standings Preview

    private func standingsPreview(_ leagueTeams: [FantasyTeamRow], myTeamID: UUID, leagueID: UUID) -> some View {
        let sorted = leagueTeams.sorted { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            return a.totalPointsFor > b.totalPointsFor
        }

        return NavigationLink {
            LeagueDashboardView(leagueID: leagueID)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, team in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.gloucester(size: 12))
                            .foregroundStyle(medalColor(for: index + 1))
                            .frame(width: 14, alignment: .trailing)

                        Text(team.teamName)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(team.id == myTeamID ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                            .fontWeight(team.id == myTeamID ? .semibold : .regular)
                            .lineLimit(1)

                        Spacer()

                        Text("\(team.wins)-\(team.losses)")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)

                        Text(String(format: "%.0f", team.totalPointsFor))
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(team.id == myTeamID ? PigeonTheme.accent.opacity(0.08) : .clear)
                }
            }
            .background(PigeonTheme.cardBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pre-Draft Card

    private func preDraftCard(_ league: FantasyLeagueRow) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 24))
                .foregroundStyle(PigeonTheme.tertiaryText)
            Text("Draft hasn't started")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)
            Text("\(league.memberUids.count) teams ready")
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(PigeonTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func rankString(_ team: FantasyTeamRow, in teams: [FantasyTeamRow]) -> String {
        let sorted = teams.sorted { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            return a.totalPointsFor > b.totalPointsFor
        }
        if let index = sorted.firstIndex(where: { $0.id == team.id }) {
            return ordinal(index + 1)
        }
        return "—"
    }

    private func ordinal(_ n: Int) -> String {
        let ones = n % 10
        let tens = (n / 10) % 10
        let suffix: String
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "pending": return ("PRE-DRAFT", PigeonTheme.tertiaryText)
            case "in_progress": return ("DRAFTING", .orange)
            case "completed": return ("ACTIVE", .green)
            default: return (status.uppercased(), PigeonTheme.tertiaryText)
            }
        }()

        return Text(label)
            .font(.gloucester(size: 9))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func letterGrade(_ rating: Double) -> String {
        switch rating {
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

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return PigeonTheme.tertiaryText
        }
    }

    // MARK: - Invite Banner

    private var inviteBanner: some View {
        VStack(spacing: 8) {
            ForEach(invites, id: \.invite.id) { item in
                HStack(spacing: 10) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.leagueName)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("League invite")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    Spacer()
                    Button {
                        Haptics.medium()
                        Task { await acceptInvite(item.invite) }
                    } label: {
                        Text("Join")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.background)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(PigeonTheme.primaryText)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .pigeonGlassSurface(cornerRadius: 12)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(PigeonTheme.tertiaryText)
            Text("no leagues yet")
                .font(.gloucester(size: 22))
                .foregroundStyle(PigeonTheme.primaryText)
            Text("Create a league and invite your friends to compete in fantasy study.")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                Haptics.medium()
                showCreateLeague = true
            } label: {
                Text("Create League")
            }
            .buttonStyle(PigeonButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !uid.isEmpty else { isLoading = false; return }

        do {
            async let leagueResult = SupabaseService.shared.fetchFantasyLeagues(forUser: uid)
            async let inviteResult = SupabaseService.shared.fetchFantasyLeagueInvites(forUser: uid)

            leagues = try await leagueResult
            let rawInvites = try await inviteResult

            var named: [(invite: LeagueInviteRow, leagueName: String)] = []
            for inv in rawInvites {
                if let league = try? await SupabaseService.shared.fetchFantasyLeague(id: inv.leagueId) {
                    named.append((inv, league.name))
                }
            }
            invites = named

            // Collect all member UIDs to batch-fetch names
            var allMemberUIDs: Set<String> = []

            for league in leagues {
                let teamRows = try await SupabaseService.shared.fetchFantasyTeams(leagueID: league.id)
                allTeams[league.id] = teamRows

                for memberUID in league.memberUids {
                    allMemberUIDs.insert(memberUID)
                }

                if let myTeam = teamRows.first(where: { $0.ownerUid == uid }) {
                    teams[league.id] = myTeam

                    let currentWeek = LeagueScoringEngine.weekNumber(for: Date(), seasonStart: league.seasonStartDate)
                    let leagueMatchups = try await SupabaseService.shared.fetchMatchups(leagueID: league.id)
                    matchups[league.id] = leagueMatchups.first { m in
                        m.weekNumber == currentWeek &&
                        (m.team1Id == myTeam.id || m.team2Id == myTeam.id)
                    }

                    let leagueTrades = try await SupabaseService.shared.fetchTrades(leagueID: league.id, teamID: myTeam.id)
                    trades[league.id] = leagueTrades.filter { $0.status == "pending" }

                    let rosterSlots = try await SupabaseService.shared.fetchRosterSlots(teamID: myTeam.id)
                    rosters[myTeam.id] = rosterSlots

                    let ratings = try await SupabaseService.shared.fetchManagerRatings(leagueID: league.id)
                    managerRatings[league.id] = ratings.first { $0.managerUid == uid }
                }
            }

            // Batch fetch display names for all members
            if !allMemberUIDs.isEmpty {
                let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: Array(allMemberUIDs))
                for profile in profiles {
                    memberNames[profile.uid.uuidString] = profile.displayName
                }
            }
        } catch {
            print("[FANTASY HOME] Load failed: \(error)")
        }

        isLoading = false
    }

    private func acceptInvite(_ invite: LeagueInviteRow) async {
        let name = currentUser?.displayName ?? "My Team"
        do {
            try await SupabaseService.shared.acceptFantasyLeagueInvite(
                inviteID: invite.id,
                leagueID: invite.leagueId,
                userUID: uid,
                teamName: "\(name)'s Team"
            )
            Haptics.success()
            await loadData()
        } catch {
            print("[FANTASY HOME] Accept invite failed: \(error)")
        }
    }
}
