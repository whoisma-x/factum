//
//  LeagueDashboardView.swift
//  Pigeon
//
//  Single league dashboard — matchups, standings, roster, draft, trades, punishments
//

import SwiftUI
import SwiftData

struct LeagueDashboardView: View {
    let leagueID: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query private var localTimelapses: [StudyTimelapse]
    @Query private var subjects: [StudySubject]

    @State private var league: FantasyLeagueRow?
    @State private var teams: [FantasyTeamRow] = []
    @State private var myTeam: FantasyTeamRow?
    @State private var rosterSlots: [RosterSlotRow] = []
    @State private var matchups: [WeeklyMatchupRow] = []
    @State private var currentMatchup: WeeklyMatchupRow?
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var managerRatings: [ManagerRatingRow] = []

    @State private var dashTab = 0
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showSettings = false
    @State private var showInvite = false
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID

    private var isCommissioner: Bool {
        league?.commissionerUid == uid
    }

    private var currentWeek: Int {
        guard let league else { return 1 }
        return LeagueScoringEngine.weekNumber(for: Date(), seasonStart: league.seasonStartDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                    .staggeredAppear(index: 0, appeared: appeared)

                leagueTabBar
                    .staggeredAppear(index: 1, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    Group {
                        switch dashTab {
                        case 0: dashboardTab
                        case 1: matchupsTab
                        case 2: standingsTab
                        case 3: rosterTab
                        case 4: draftTab
                        case 5: moreTab
                        default: EmptyView()
                        }
                    }
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
        .sheet(isPresented: $showSettings) {
            if let league {
                LeagueSettingsView(league: league) {
                    Task { await loadData() }
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteToLeagueView(leagueID: leagueID)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(league?.name ?? "League")
                    .font(PigeonTheme.titleFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                HStack(spacing: 8) {
                    if let myTeam {
                        Text("\(myTeam.wins)-\(myTeam.losses)\(myTeam.ties > 0 ? "-\(myTeam.ties)" : "")")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Week \(currentWeek)")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    if isCommissioner {
                        Text("COMMISH")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.background)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PigeonTheme.primaryText)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Menu {
                Button { showInvite = true } label: {
                    Label("Invite Members", systemImage: "person.badge.plus")
                }
                if isCommissioner {
                    Button { showSettings = true } label: {
                        Label("League Settings", systemImage: "gear")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.gloucester(size: 22))
                    .foregroundStyle(PigeonTheme.secondaryText)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Dashboard Tab (Overview)

    private var dashboardTab: some View {
        VStack(spacing: 16) {
            // This Week's Matchup
            if let matchup = currentMatchup, let league {
                VStack(alignment: .leading, spacing: 10) {
                    Text("THIS WEEK'S MATCHUP")
                        .pigeonSectionTitle()
                    NavigationLink {
                        WeeklyMatchupView(matchup: matchup, leagueID: leagueID)
                    } label: {
                        matchupScoreboard(matchup, league: league)
                    }
                    .buttonStyle(.plain)
                }
            }

            // My Team Snapshot
            if let myTeam {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MY TEAM")
                        .pigeonSectionTitle()

                    PigeonStatRow(stats: [
                        (value: String(format: "%.0f", myTeam.totalPointsFor), label: "PF"),
                        (value: String(format: "%.0f", myTeam.totalPointsAgainst), label: "PA"),
                        (value: "\(myTeam.wins)-\(myTeam.losses)", label: "Record"),
                    ])
                }
            }

            // Manager Rating
            if let myRating = managerRatings.first(where: { $0.managerUid == uid }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MANAGER RATING")
                        .pigeonSectionTitle()
                    NavigationLink {
                        ManagerRatingView(leagueID: leagueID)
                    } label: {
                        HStack(spacing: 14) {
                            Text(letterGrade(myRating.overallRating))
                                .font(.gloucester(size: 32))
                                .foregroundStyle(PigeonTheme.primaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.0f", myRating.overallRating))
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text("overall rating")
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        .padding(16)
                        .pigeonGlassSurface(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick Standings
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STANDINGS")
                        .pigeonSectionTitle()
                    Spacer()
                    Button {
                        withAnimation { dashTab = 2 }
                    } label: {
                        Text("See All")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(sortedTeams.prefix(5).enumerated()), id: \.element.id) { index, team in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(medalColor(for: index + 1))
                                .frame(width: 20)
                            Text(team.teamName)
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(team.id == myTeam?.id ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                                .lineLimit(1)
                            Spacer()
                            Text("\(team.wins)-\(team.losses)")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        if index < min(sortedTeams.count, 5) - 1 {
                            Divider().overlay(PigeonTheme.separator)
                        }
                    }
                }
                .pigeonGlassSurface(cornerRadius: 14)
            }
        }
    }

    // MARK: - Matchups Tab

    private var matchupsTab: some View {
        VStack(spacing: 12) {
            if matchups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 40))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    Text("No matchups scheduled yet")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .padding(.top, 40)
            } else if let league {
                let weekMatchups = matchups.filter { $0.weekNumber == currentWeek }
                if !weekMatchups.isEmpty {
                    Text("WEEK \(currentWeek)")
                        .pigeonSectionTitle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(weekMatchups, id: \.id) { matchup in
                    NavigationLink {
                        WeeklyMatchupView(matchup: matchup, leagueID: leagueID)
                    } label: {
                        matchupScoreboard(matchup, league: league)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Standings Tab

    private var standingsTab: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 24, alignment: .leading)
                Text("TEAM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("W")
                    .frame(width: 28, alignment: .center)
                Text("L")
                    .frame(width: 28, alignment: .center)
                Text("PF")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.gloucester(size: 11))
            .foregroundStyle(PigeonTheme.tertiaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().overlay(PigeonTheme.separator)

            ForEach(Array(sortedTeams.enumerated()), id: \.element.id) { index, team in
                NavigationLink {
                    OpponentTeamView(teamID: team.id, leagueID: leagueID)
                } label: {
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(medalColor(for: index + 1))
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(team.teamName)
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .lineLimit(1)
                            Text(memberProfiles[team.ownerUid]?.displayName ?? "")
                                .font(.gloucester(size: 11))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(team.wins)")
                            .font(PigeonTheme.captionFont)
                            .frame(width: 28, alignment: .center)
                        Text("\(team.losses)")
                            .font(PigeonTheme.captionFont)
                            .frame(width: 28, alignment: .center)
                        Text(String(format: "%.0f", team.totalPointsFor))
                            .font(PigeonTheme.smallFont)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .foregroundStyle(PigeonTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if index < sortedTeams.count - 1 {
                    if index + 1 == league?.playoffTeamCount {
                        // Playoff cutoff line
                        HStack(spacing: 6) {
                            Rectangle().fill(.orange.opacity(0.4)).frame(height: 1)
                            Text("PLAYOFFS")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(.orange.opacity(0.6))
                            Rectangle().fill(.orange.opacity(0.4)).frame(height: 1)
                        }
                        .padding(.horizontal, 14)
                    } else {
                        Divider().overlay(PigeonTheme.separator).padding(.leading, 14)
                    }
                }
            }
        }
        .pigeonGlassSurface(cornerRadius: 14)
    }

    // MARK: - Roster Tab

    private var rosterTab: some View {
        NavigationLink {
            MyTeamView(leagueID: leagueID)
        } label: {
            VStack(spacing: 12) {
                let mySlots = rosterSlots.filter { $0.teamId == myTeam?.id }
                let active = mySlots.filter { $0.isActive }
                let bench = mySlots.filter { !$0.isActive }

                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("STARTERS")
                                .pigeonSectionTitle()
                            Spacer()
                            Text("\(active.count)/\(league?.maxRosterSize ?? 0)")
                                .font(.gloucester(size: 11))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        ForEach(active, id: \.id) { slot in
                            rosterSlotPreview(slot)
                        }
                    }
                }

                if !bench.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BENCH")
                            .pigeonSectionTitle()
                        ForEach(bench, id: \.id) { slot in
                            rosterSlotPreview(slot)
                        }
                    }
                }

                if mySlots.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.system(size: 36))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("Draft hasn't started yet")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .padding(.top, 40)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rosterSlotPreview(_ slot: RosterSlotRow) -> some View {
        let subjectColor = StudySubject.color(for: slot.subjectName, in: subjects)
        let score = computeSlotScore(slot)

        return HStack(spacing: 0) {
            // Subject color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(subjectColor)
                .frame(width: 4, height: 34)

            HStack(spacing: 8) {
                if slot.isActive && slot.multiplier > 1 {
                    Text("\(slot.multiplier)×")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(slot.multiplier == 3 ? .orange : .blue)
                        .frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
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

                Spacer()

                Text(String(format: "%.1f", score))
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 12)
        .pigeonGlassSurface(cornerRadius: 10)
    }

    // MARK: - Draft Tab

    private var draftTab: some View {
        VStack(spacing: 16) {
            if league?.draftStatus == "pending" {
                VStack(spacing: 16) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(PigeonTheme.tertiaryText)

                    Text("Draft hasn't started")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)

                    Text("\(teams.count) teams in the league")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)

                    if isCommissioner {
                        NavigationLink {
                            DraftLobbyView(leagueID: leagueID)
                        } label: {
                            Text("Set Up Draft")
                        }
                        .buttonStyle(PigeonButtonStyle())
                    } else {
                        Text("Waiting for the commissioner to start the draft")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)
            } else if league?.draftStatus == "in_progress" {
                NavigationLink {
                    DraftRoomView(leagueID: leagueID)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Draft In Progress")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                            }
                            Text("Tap to join the draft room")
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .padding(16)
                    .pigeonGlassSurface(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    DraftResultsView(leagueID: leagueID)
                } label: {
                    Text("View Draft Results")
                }
                .buttonStyle(PigeonButtonStyle(filled: false))
            }
        }
    }

    // MARK: - More Tab

    private var moreTab: some View {
        VStack(spacing: 10) {
            moreRow(icon: "arrow.triangle.2.circlepath", title: "Trades", subtitle: "Propose and manage trades") {
                TradeView(leagueID: leagueID)
            }
            moreRow(icon: "person.badge.plus", title: "Free Agents", subtitle: "Pick up unclaimed players") {
                FreeAgentView(leagueID: leagueID)
            }
            moreRow(icon: "exclamationmark.triangle.fill", title: "Punishments", subtitle: "Weekly punishments and votes") {
                PunishmentView(leagueID: leagueID)
            }
            moreRow(icon: "chart.bar.fill", title: "Manager Ratings", subtitle: "How managers stack up") {
                ManagerRatingView(leagueID: leagueID)
            }
            moreRow(icon: "sportscourt", title: "Playoffs", subtitle: "Bracket and seeding") {
                PlayoffBracketView(leagueID: leagueID)
            }
        }
    }

    private func moreRow<Dest: View>(icon: String, title: String, subtitle: String, @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.gloucester(size: 18))
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text(subtitle)
                        .font(.gloucester(size: 12))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
            .padding(14)
            .pigeonGlassSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - League Tab Bar (Yahoo Fantasy style)

    @Namespace private var tabNS

    private let tabItems: [(id: Int, label: String, icon: String)] = [
        (0, "Home", "house.fill"),
        (1, "Matchups", "sportscourt.fill"),
        (2, "Standings", "list.number"),
        (3, "Roster", "person.3.fill"),
        (4, "Draft", "list.clipboard.fill"),
        (5, "More", "ellipsis"),
    ]

    private var leagueTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabItems, id: \.id) { item in
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { dashTab = item.id }
                        } label: {
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .font(.gloucester(size: 13))
                                    Text(item.label)
                                        .font(.gloucester(size: 14))
                                }
                                .foregroundStyle(dashTab == item.id ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 6)

                                ZStack(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 3)
                                    if dashTab == item.id {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(PigeonTheme.primaryText)
                                            .frame(height: 3)
                                            .matchedGeometryEffect(id: "leagueTab", in: tabNS)
                                    }
                                }
                            }
                        }
                        .id(item.id)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(PigeonTheme.separator)
                    .frame(height: 1)
            }
            .onChange(of: dashTab) { _, newTab in
                withAnimation { proxy.scrollTo(newTab, anchor: .center) }
            }
        }
    }

    // MARK: - Matchup Scoreboard Card

    private func matchupScoreboard(_ matchup: WeeklyMatchupRow, league: FantasyLeagueRow) -> some View {
        let team1Name = teams.first(where: { $0.id == matchup.team1Id })?.teamName ?? "Team 1"
        let team2Name = teams.first(where: { $0.id == matchup.team2Id })?.teamName ?? "Team 2"
        let s1 = matchup.team1Score
        let s2 = matchup.team2Score

        return VStack(spacing: 0) {
            // Week label
            HStack {
                Text("WEEK \(matchup.weekNumber)")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Spacer()
                if matchup.isBye {
                    Text("BYE")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Scores
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(team1Name)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Text(String(format: "%.1f", s1))
                        .font(.gloucester(size: 32))
                        .foregroundStyle(s1 >= s2 ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)

                Text("—")
                    .font(.gloucester(size: 20))
                    .foregroundStyle(PigeonTheme.tertiaryText)

                VStack(spacing: 2) {
                    Text(team2Name)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Text(String(format: "%.1f", s2))
                        .font(.gloucester(size: 32))
                        .foregroundStyle(s2 >= s1 ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .pigeonGlassSurface(cornerRadius: 14)
    }

    // MARK: - Helpers

    private var sortedTeams: [FantasyTeamRow] {
        teams.sorted { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            return a.totalPointsFor > b.totalPointsFor
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

    private func computeSlotScore(_ slot: RosterSlotRow) -> Double {
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
        return result.multipliedScore
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            async let leagueResult = SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            async let teamsResult = SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            async let rosterResult = SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            async let matchupsResult = SupabaseService.shared.fetchMatchups(leagueID: leagueID)
            async let ratingsResult = SupabaseService.shared.fetchManagerRatings(leagueID: leagueID)

            league = try await leagueResult
            teams = try await teamsResult
            rosterSlots = try await rosterResult
            matchups = try await matchupsResult
            managerRatings = try await ratingsResult

            myTeam = teams.first(where: { $0.ownerUid == uid })
            currentMatchup = matchups.first(where: { matchup in
                matchup.weekNumber == currentWeek &&
                (matchup.team1Id == myTeam?.id || matchup.team2Id == myTeam?.id)
            })

            if let league {
                let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
                for profile in profiles {
                    memberProfiles[profile.uid.uuidString] = profile
                }
            }
        } catch {
            print("[LEAGUE] Dashboard load failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Invite To League View

struct InviteToLeagueView: View {
    let leagueID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [UserRow] = []
    @State private var sentInvites: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Search by @username", text: $searchText)
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    .padding(.horizontal, 20)
                    .onChange(of: searchText) { _, newValue in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await performSearch(newValue)
                        }
                    }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults, id: \.uid) { user in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(PigeonTheme.accent)
                                        .frame(width: 40, height: 40)
                                    Text(String(user.displayName.prefix(1)))
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    if let username = user.username {
                                        Text("@\(username)")
                                            .font(.gloucester(size: 12))
                                            .foregroundStyle(PigeonTheme.tertiaryText)
                                    }
                                }
                                Spacer()
                                if sentInvites.contains(user.uid.uuidString) {
                                    Text("Invited")
                                        .font(.gloucester(size: 12))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                } else {
                                    Button {
                                        Haptics.light()
                                        Task { await sendInvite(user) }
                                    } label: {
                                        Text("Invite")
                                            .font(PigeonTheme.smallFont)
                                            .foregroundStyle(PigeonTheme.background)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 7)
                                            .background(PigeonTheme.primaryText)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(12)
                            .pigeonGlassSurface(cornerRadius: 10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 16)
            .background(PigeonTheme.background)
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
        }
    }

    private func performSearch(_ query: String) async {
        let cleaned = query.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2 else { searchResults = []; return }
        do {
            let results = try await SupabaseService.shared.searchUsers(query: cleaned)
            let uid = AuthService.shared.currentUserID
            searchResults = results.filter { $0.uid.uuidString != uid }
        } catch {
            print("[LEAGUE] Search failed: \(error)")
        }
    }

    private func sendInvite(_ user: UserRow) async {
        let uid = AuthService.shared.currentUserID
        do {
            try await SupabaseService.shared.inviteToFantasyLeague(
                leagueID: leagueID,
                inviterUID: uid,
                inviteeUID: user.uid.uuidString
            )
            sentInvites.insert(user.uid.uuidString)
            Haptics.success()
        } catch {
            print("[LEAGUE] Invite failed: \(error)")
        }
    }
}
