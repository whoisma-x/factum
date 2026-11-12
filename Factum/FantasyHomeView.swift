//
//  FantasyHomeView.swift
//  Pigeon
//
//  Fantasy league home dashboard — clean overview of your leagues

import SwiftUI
import SwiftData

struct FantasyHomeView: View {
    @Binding var showCamera: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query private var localTimelapses: [StudyTimelapse]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]

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
    @State private var loadError = false
    @State private var appeared = false
    @State private var showCreateLeague = false
    @State private var frozenGreeting: String? = nil
    @AppStorage("homeStatsPeriod") private var statsPeriod: Int = 0 // 0=today, 1=week, 2=month, 3=year

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
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("League")
                                    .font(.gloucester(size: 12))
                            }
                            .foregroundStyle(PigeonTheme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PigeonTheme.primaryText)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 8)
                    .staggeredAppear(index: 0, appeared: appeared)

                    // Study stats: hours studied + streak
                    studyStatsRow
                        .staggeredAppear(index: 1, appeared: appeared)

                    // Study Quotas progress card
                    if let user = currentUser, !user.studyQuotas.isEmpty {
                        quotaCard(user: user)
                            .staggeredAppear(index: 2, appeared: appeared)
                    }

                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("loading leagues...")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if loadError {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 28))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                            Text("Couldn't load leagues")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                            Button {
                                Haptics.light()
                                Task { await loadData() }
                            } label: {
                                Text("Retry")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.background)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(PigeonTheme.primaryText)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        if !invites.isEmpty {
                            inviteBanner
                                .staggeredAppear(index: 3, appeared: appeared)
                        }

                        if leagues.isEmpty {
                            emptyState
                                .staggeredAppear(index: 4, appeared: appeared)
                        } else {
                            ForEach(Array(leagues.enumerated()), id: \.element.id) { index, league in
                                leagueSection(league)
                                    .staggeredAppear(index: index + 4, appeared: appeared)
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

    // MARK: - Greeting

    private static let generalGreetings = [
        "coo coo", "spread your wings", "don't be a bird brain",
        "time to ruffle some pages", "nest up and focus", "fly through those notes",
        "peck away at it", "feathers down, books open", "wings up",
        "carrier pigeon mode: on", "flocking to the books", "perched and ready",
        "hatching some knowledge", "this pigeon doesn't rest",
        "coo'd you study any harder", "let's get cooing", "pigeon brain activated",
        "strut your stuff", "delivering grades, one coo at a time",
        "no crumbs, only textbooks", "this nest runs on focus",
        "pecking order: you, then everyone else", "stay on the perch",
        "beak deep in the books", "bread crumbs can wait", "fly above the average",
        "pigeon post: you got this", "the flock is proud of you",
        "one coo at a time", "let's wing this", "bob your head and get to work",
        "homing in on those grades", "even pigeons grind",
    ]

    private static var timeOfDayGreetings: [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return ["early bird gets the A", "rise and grind, pigeon", "morning coo, time to study", "fresh feathers, fresh start", "up with the pigeons"]
        case 12..<17: return ["midday study flight", "peak hours, peak focus", "noon coo, lock in", "no nap, only notes"]
        case 17..<21: return ["evening coo, still at it", "sunset study session", "golden hour for golden grades", "twilight grind"]
        default: return ["night owl pigeon mode", "moonlit study sesh", "burning the midnight feathers", "quiet hours, loud progress"]
        }
    }

    private var greeting: String {
        if let frozenGreeting { return frozenGreeting }
        let pool = Self.generalGreetings + Self.timeOfDayGreetings
        return pool.randomElement() ?? "coo coo"
    }

    private var firstName: String {
        let name = currentUser?.displayName ?? "Student"
        return name.components(separatedBy: " ").first ?? name
    }

    // MARK: - Study Stats Row

    private var userTimelapses: [StudyTimelapse] {
        localTimelapses.filter { $0.authorID == uid }
    }

    private var statsPeriodLabel: String {
        switch statsPeriod {
        case 1: return "This Week"
        case 2: return "This Month"
        case 3: return "This Year"
        default: return "Today"
        }
    }

    private var statsPeriodMinutes: Int {
        let cal = Calendar.current
        switch statsPeriod {
        case 1:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
            return totalMinutes(since: interval.start)
        case 2:
            guard let interval = cal.dateInterval(of: .month, for: Date()) else { return 0 }
            return totalMinutes(since: interval.start)
        case 3:
            guard let interval = cal.dateInterval(of: .year, for: Date()) else { return 0 }
            return totalMinutes(since: interval.start)
        default:
            return totalMinutes(since: cal.startOfDay(for: Date()))
        }
    }

    private func totalMinutes(since date: Date) -> Int {
        userTimelapses
            .filter { $0.createdAt >= date }
            .reduce(0) { $0 + $1.durationSeconds } / 60
    }

    private var streakDays: Int {
        guard !userTimelapses.isEmpty else { return 0 }
        let cal = Calendar.current
        let studyDates = Set(userTimelapses.map { cal.startOfDay(for: $0.createdAt) })
        let today = cal.startOfDay(for: Date())
        var checkDate = today
        if !studyDates.contains(checkDate) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = yesterday
            if !studyDates.contains(checkDate) { return 0 }
        }
        var streak = 0
        while studyDates.contains(checkDate) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    private var studyStatsRow: some View {
        VStack(spacing: 16) {
            // Pigeon pun greeting
            Text("\(greeting), \(firstName).")
                .font(.gloucester(size: 16))
                .foregroundStyle(PigeonTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats: hours studied + streak — floating, no pill
            HStack(spacing: 0) {
                // Hours studied — long press to change period
                VStack(spacing: 4) {
                    Text(formatQuotaTime(statsPeriodMinutes))
                        .font(.gloucester(size: 26))
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text(statsPeriodLabel)
                        .font(.gloucester(size: 10))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                .onLongPressGesture(minimumDuration: 0.3) {
                    Haptics.medium()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        statsPeriod = (statsPeriod + 1) % 4
                    }
                }

                // Divider
                Rectangle()
                    .fill(PigeonTheme.separator)
                    .frame(width: 1, height: 28)

                // Day streak
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(streakDays)")
                            .font(.gloucester(size: 26))
                            .foregroundStyle(PigeonTheme.primaryText)
                        if streakDays > 0 {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Day Streak")
                        .font(.gloucester(size: 10))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if frozenGreeting == nil { frozenGreeting = greeting }
        }
    }

    // MARK: - Study Quota Card

    private func quotaCard(user: UserProfile) -> some View {
        let quotas = activeQuotas(for: user)
        let progressItems = quotas.map { quotaProgress(for: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("STUDY QUOTAS")
                .font(.gloucester(size: 11))
                .foregroundStyle(PigeonTheme.secondaryText)
                .tracking(1.5)

            ForEach(Array(zip(quotas, progressItems)), id: \.0.id) { quota, progress in
                let pct = progress.target > 0 ? min(Double(progress.done) / Double(progress.target), 1.0) : 0
                let color = StudySubject.color(for: quota.subjectName, in: subjects)

                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(quota.subjectName)
                        .font(.gloucester(size: 12))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(pct >= 1.0 ? quotaGreen : PigeonTheme.secondaryText)
                    Text(progress.label)
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.secondaryText)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(PigeonTheme.secondaryText.opacity(0.15))
                            .frame(height: 4)
                        Capsule()
                            .fill(pct >= 1.0 ? quotaGreen : color)
                            .frame(width: geo.size.width * pct, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(16)
        .pigeonGlassSurface(cornerRadius: 16)
    }

    // MARK: - Quota Progress Helpers

    private func activeQuotas(for user: UserProfile) -> [StudyQuota] {
        let cal = Calendar.current
        return user.studyQuotas.filter { quota in
            if quota.frequency == .oneTime {
                return (quota.deadline ?? Date()) >= cal.startOfDay(for: Date())
            }
            return true
        }
    }

    private func quotaProgress(for quota: StudyQuota) -> (done: Int, target: Int, label: String) {
        let cal = Calendar.current
        switch quota.frequency {
        case .daily:
            let done = todaySubjectMinutes()[quota.subjectName, default: 0]
            return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))")
        case .weekly:
            let done = subjectMinutes(for: quota.subjectName, in: .weekOfYear)
            return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))")
        case .monthly:
            let done = subjectMinutes(for: quota.subjectName, in: .month)
            return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))")
        case .yearly:
            let done = subjectMinutes(for: quota.subjectName, in: .year)
            return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))")
        case .scheduled:
            let today = cal.component(.weekday, from: Date())
            let isToday = quota.scheduledDays?.contains { $0.calendarWeekday == today } ?? false
            if isToday {
                let done = todaySubjectMinutes()[quota.subjectName, default: 0]
                return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))")
            } else {
                return (0, quota.targetMinutes, "not scheduled today")
            }
        case .oneTime:
            let done = allTimeSubjectMinutes(for: quota.subjectName, since: quota.createdAt)
            let daysLeft = cal.dateComponents([.day], from: Date(), to: quota.deadline ?? Date()).day ?? 0
            let suffix = daysLeft > 0 ? " (\(daysLeft)d left)" : ""
            return (done, quota.targetMinutes, "\(formatQuotaTime(done))/\(formatQuotaTime(quota.targetMinutes))\(suffix)")
        }
    }

    private func todaySubjectMinutes() -> [String: Int] {
        var result: [String: Int] = [:]
        let cal = Calendar.current
        for tl in userTimelapses where cal.isDateInToday(tl.createdAt) {
            for seg in tl.subjectSegments {
                result[seg.subject, default: 0] += seg.seconds / 60
            }
        }
        return result
    }

    private func subjectMinutes(for subject: String, in component: Calendar.Component) -> Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: component, for: Date()) else { return 0 }
        var total = 0
        for tl in userTimelapses where tl.createdAt >= interval.start {
            for seg in tl.subjectSegments where seg.subject == subject {
                total += seg.seconds / 60
            }
        }
        return total
    }

    private func allTimeSubjectMinutes(for subject: String, since date: Date) -> Int {
        var total = 0
        for tl in userTimelapses where tl.createdAt >= date {
            for seg in tl.subjectSegments where seg.subject == subject {
                total += seg.seconds / 60
            }
        }
        return total
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
                        .foregroundStyle(isWinning ? quotaGreen : PigeonTheme.destructive)
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
        .padding(.vertical, 16)
        .pigeonGlassSurface(cornerRadius: 12)
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
                    value: String(format: "%.0f", rating.overallRating),
                    label: "Rating"
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.gloucester(size: 15))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(.gloucester(size: 10))
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
                    .background(PigeonTheme.destructive)
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(highlight ? PigeonTheme.destructive : PigeonTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .pigeonGlassSurface(cornerRadius: 10)
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
            .pigeonGlassSurface(cornerRadius: 10)
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
        .pigeonGlassSurface(cornerRadius: 10)
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
            case "in_progress": return ("DRAFTING", Color(red: 0.85, green: 0.55, blue: 0.15))
            case "completed": return ("ACTIVE", quotaGreen)
            default: return (status.uppercased(), PigeonTheme.tertiaryText)
            }
        }()

        return Text(label)
            .font(.gloucester(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.15))
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
        loadError = false

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
            loadError = leagues.isEmpty
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
