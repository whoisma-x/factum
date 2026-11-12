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
    @State private var punishments: [PunishmentRow] = []
    @State private var showProposePunishment = false
    private let votesPerMember = 3 // configurable: how many pool votes each member gets per week

    @State private var dashTab = 0
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showSettings = false
    @State private var showInvite = false
    @State private var selectedWeek: Int?
    @Environment(\.dismiss) private var dismiss

    // Drag state for roster tab
    @State private var draggingSlotID: UUID?
    @State private var rosterDragSaving = false

    private enum RosterDragTarget: Equatable {
        case starter(index: Int)
        case bench(slotID: UUID)
    }

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
                        case 5: punishmentsTab
                        case 6: moreTab
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
            // Current / Latest Matchup
            if let matchup = currentMatchup, let league {
                VStack(alignment: .leading, spacing: 10) {
                    Text(matchup.weekNumber == currentWeek ? "THIS WEEK'S MATCHUP" : "LATEST MATCHUP")
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
                            Text(String(format: "%.0f", myRating.overallRating))
                                .font(.gloucester(size: 32))
                                .foregroundStyle(PigeonTheme.primaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("manager rating")
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

    private var displayedWeek: Int {
        selectedWeek ?? defaultWeek
    }

    /// Show current week if it has matchups, otherwise fall back to the latest week with data.
    private var defaultWeek: Int {
        let hasCurrentWeekMatchups = matchups.contains { $0.weekNumber == currentWeek }
        if hasCurrentWeekMatchups { return currentWeek }
        return matchups.map(\.weekNumber).max() ?? currentWeek
    }

    private var maxWeek: Int {
        max(matchups.map(\.weekNumber).max() ?? currentWeek, currentWeek)
    }

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
                    if isCommissioner {
                        Text("Go to Settings to generate matchups")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .padding(.top, 40)
            } else if let league {
                // Week selector
                HStack(spacing: 16) {
                    Button {
                        Haptics.light()
                        withAnimation { selectedWeek = max(1, displayedWeek - 1) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(displayedWeek > 1 ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                    }
                    .disabled(displayedWeek <= 1)

                    VStack(spacing: 2) {
                        Text("WEEK \(displayedWeek)")
                            .font(.gloucester(size: 16))
                            .foregroundStyle(PigeonTheme.primaryText)
                        if displayedWeek == currentWeek {
                            Text("current")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(quotaGreen)
                        } else {
                            let weekMatchups = matchups.filter { $0.weekNumber == displayedWeek }
                            let isFinalized = weekMatchups.allSatisfy { $0.winnerTeamId != nil || $0.isBye }
                            Text(isFinalized ? "final" : "scheduled")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(isFinalized ? PigeonTheme.tertiaryText : Color(red: 0.85, green: 0.55, blue: 0.15))
                        }
                    }

                    Button {
                        Haptics.light()
                        withAnimation { selectedWeek = min(maxWeek, displayedWeek + 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(displayedWeek < maxWeek ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                    }
                    .disabled(displayedWeek >= maxWeek)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Jump to current week button (if not viewing current)
                if displayedWeek != currentWeek {
                    Button {
                        Haptics.light()
                        withAnimation { selectedWeek = nil }
                    } label: {
                        Text("Go to Current Week")
                            .font(.gloucester(size: 12))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }

                // Week matchups
                let weekMatchups = matchups.filter { $0.weekNumber == displayedWeek }
                if weekMatchups.isEmpty {
                    Text("No matchups this week")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .padding(.top, 20)
                } else {
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
    }

    // MARK: - Standings Tab

    private var standingsTab: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 18, alignment: .leading)
                Text("TEAM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("W")
                    .frame(width: 20, alignment: .center)
                Text("L")
                    .frame(width: 20, alignment: .center)
                Text("PF")
                    .frame(width: 36, alignment: .trailing)
                Text("AVG")
                    .frame(width: 36, alignment: .trailing)
                Text("STK")
                    .frame(width: 32, alignment: .trailing)
            }
            .font(.gloucester(size: 10))
            .foregroundStyle(PigeonTheme.tertiaryText)
            .padding(.horizontal, 12)
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
                            .frame(width: 18, alignment: .leading)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(team.teamName)
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(team.id == myTeam?.id ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                                    .lineLimit(1)
                                if team.id == myTeam?.id {
                                    Text("YOU")
                                        .font(.gloucester(size: 8))
                                        .foregroundStyle(PigeonTheme.background)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(PigeonTheme.primaryText)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            Text(memberProfiles[team.ownerUid]?.displayName ?? "")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(team.wins)")
                            .font(PigeonTheme.captionFont)
                            .frame(width: 20, alignment: .center)
                        Text("\(team.losses)")
                            .font(PigeonTheme.captionFont)
                            .frame(width: 20, alignment: .center)
                        Text(String(format: "%.0f", team.totalPointsFor))
                            .font(.gloucester(size: 11))
                            .frame(width: 36, alignment: .trailing)

                        let gamesPlayed = team.wins + team.losses + team.ties
                        let avgPF = gamesPlayed > 0 ? team.totalPointsFor / Double(gamesPlayed) : 0
                        Text(String(format: "%.1f", avgPF))
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 36, alignment: .trailing)

                        let streak = streakString(for: team.id)
                        Text(streak)
                            .font(.gloucester(size: 11))
                            .foregroundStyle(streak.hasPrefix("W") ? quotaGreen : streak.hasPrefix("L") ? PigeonTheme.destructive : PigeonTheme.tertiaryText)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .foregroundStyle(PigeonTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if index < sortedTeams.count - 1 {
                    if index + 1 == league?.playoffTeamCount {
                        // Playoff cutoff line
                        HStack(spacing: 6) {
                            Rectangle().fill(Color(red: 0.85, green: 0.55, blue: 0.15).opacity(0.35)).frame(height: 1)
                            Text("PLAYOFFS")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.15).opacity(0.6))
                            Rectangle().fill(Color(red: 0.85, green: 0.55, blue: 0.15).opacity(0.35)).frame(height: 1)
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

    /// Compute the current win/loss streak for a team from finalized matchups.
    private func streakString(for teamID: UUID) -> String {
        let teamMatchups = matchups
            .filter { ($0.team1Id == teamID || $0.team2Id == teamID) && $0.winnerTeamId != nil && !$0.isBye }
            .sorted { $0.weekNumber > $1.weekNumber }

        guard let first = teamMatchups.first else { return "-" }
        let firstWon = first.winnerTeamId == teamID
        var count = 0
        for m in teamMatchups {
            let won = m.winnerTeamId == teamID
            if won == firstWon { count += 1 } else { break }
        }
        return "\(firstWon ? "W" : "L")\(count)"
    }

    // MARK: - Roster Tab

    /// The multiplier config for each active slot position, sorted highest-first.
    private var slotPositions: [Int] {
        (league?.slotMultipliers ?? []).sorted(by: >)
    }

    /// Active roster slots ordered to match slot positions (highest multiplier first).
    private var orderedActiveSlots: [RosterSlotRow?] {
        let mySlots = rosterSlots.filter { $0.teamId == myTeam?.id && $0.isActive }
            .sorted { $0.multiplier > $1.multiplier }  // highest multiplier first

        let positions = slotPositions
        guard !positions.isEmpty else { return [] }

        // Greedily assign players to slots: for each slot position, pick the first
        // unassigned player whose multiplier matches, or any remaining player.
        var available = mySlots
        var result: [RosterSlotRow?] = []

        for mult in positions {
            if let idx = available.firstIndex(where: { $0.multiplier == mult }) {
                result.append(available.remove(at: idx))
            } else if let first = available.first {
                result.append(available.removeFirst())
                _ = first // suppress warning
            } else {
                result.append(nil)
            }
        }
        return result
    }

    private var rosterTab: some View {
        let mySlots = rosterSlots.filter { $0.teamId == myTeam?.id }
        let bench = mySlots.filter { !$0.isActive }.sorted { $0.acquiredDate < $1.acquiredDate }
        let positions = slotPositions
        let activeSlotsList = orderedActiveSlots
        let filledCount = activeSlotsList.compactMap({ $0 }).count
        let isDragging = draggingSlotID != nil

        return VStack(spacing: 16) {
            // Team stats
            if let myTeam {
                PigeonStatRow(stats: [
                    (value: "\(myTeam.wins)-\(myTeam.losses)", label: "Record"),
                    (value: String(format: "%.0f", myTeam.totalPointsFor), label: "Total PF"),
                    (value: "\(mySlots.count)", label: "Roster"),
                ])
            }

            // Starters — fixed slot positions
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STARTERS")
                        .pigeonSectionTitle()
                    Spacer()
                    Text("\(filledCount)/\(positions.count)")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }

                rosterHeader

                ForEach(Array(positions.enumerated()), id: \.offset) { index, mult in
                    if let slot = activeSlotsList[index] {
                        rosterPlayerRow(slot, slotIndex: index, slotMultiplier: mult, canBench: true)
                            .opacity(draggingSlotID == slot.id ? 0.4 : 1.0)
                            .scaleEffect(draggingSlotID == slot.id ? 0.95 : 1.0)
                            .onLongPressGesture(minimumDuration: 0.3) {
                                guard !rosterDragSaving else { return }
                                Haptics.medium()
                                withAnimation(.easeInOut(duration: 0.15)) { draggingSlotID = slot.id }
                            }
                            .onTapGesture {
                                if let dragging = draggingSlotID, dragging != slot.id {
                                    Task { await handleRosterDrop(draggedID: dragging, toStarter: index) }
                                }
                            }
                    } else {
                        emptySlotRow(index: index, multiplier: mult)
                            .onTapGesture {
                                if let dragging = draggingSlotID {
                                    Task { await handleRosterDrop(draggedID: dragging, toStarter: index) }
                                }
                            }
                    }
                }
            }

            // Bench — always show
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("BENCH")
                        .pigeonSectionTitle()
                    Spacer()
                    Text("\(bench.count)/\(league?.benchSize ?? 2)")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }

                if bench.isEmpty && isDragging {
                    rosterBenchDropTarget
                } else if bench.isEmpty {
                    Text("Bench is empty")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .padding(.vertical, 12)
                } else {
                    ForEach(bench, id: \.id) { slot in
                        rosterPlayerRow(slot, slotIndex: nil, slotMultiplier: 1, canBench: false)
                            .opacity(draggingSlotID == slot.id ? 0.4 : 1.0)
                            .scaleEffect(draggingSlotID == slot.id ? 0.95 : 1.0)
                            .onLongPressGesture(minimumDuration: 0.3) {
                                guard !rosterDragSaving else { return }
                                Haptics.medium()
                                withAnimation(.easeInOut(duration: 0.15)) { draggingSlotID = slot.id }
                            }
                            .onTapGesture {
                                if let dragging = draggingSlotID, dragging != slot.id {
                                    Task { await handleRosterBenchSwap(draggedID: dragging, benchSlotID: slot.id) }
                                }
                            }
                    }
                    if isDragging {
                        rosterBenchDropTarget
                    }
                }
            }

            // Cancel drag
            if isDragging {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draggingSlotID = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel move")
                    }
                    .font(.gloucester(size: 13))
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .pigeonGlassSurface(cornerRadius: 10)
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

    private var rosterBenchDropTarget: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 13, weight: .medium))
            Text("Tap to bench")
                .font(.gloucester(size: 12))
        }
        .foregroundStyle(PigeonTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PigeonTheme.secondaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PigeonTheme.secondaryText.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
        )
        .onTapGesture {
            if let dragging = draggingSlotID {
                Task { await handleRosterBench(slotID: dragging) }
            }
        }
    }

    /// Empty slot placeholder row showing the multiplier and "(empty)".
    private func emptySlotRow(index: Int, multiplier: Int) -> some View {
        HStack(spacing: 8) {
            // Multiplier badge
            Text("\(multiplier)×")
                .font(.gloucester(size: 11))
                .foregroundStyle(multiplierColor(multiplier).opacity(0.8))
                .frame(width: 28, height: 22)
                .background(multiplierColor(multiplier).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(draggingSlotID != nil ? "Tap to place here" : "(empty)")
                .font(.gloucester(size: 13))
                .foregroundStyle(draggingSlotID != nil ? multiplierColor(multiplier) : PigeonTheme.tertiaryText.opacity(0.6))
                .italic()

            Spacer()

            Text("—")
                .font(.gloucester(size: 14))
                .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.4))
                .frame(width: 56, alignment: .trailing)

            Color.clear.frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .pigeonGlassSurface(cornerRadius: 12)
        .opacity(draggingSlotID != nil ? 0.85 : 0.55)
    }

    private var rosterHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 34) // slot badge width
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("WK PTS")
                .frame(width: 56, alignment: .trailing)
            Color.clear.frame(width: 30)
        }
        .font(.gloucester(size: 10))
        .foregroundStyle(PigeonTheme.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func rosterPlayerRow(_ slot: RosterSlotRow, slotIndex: Int?, slotMultiplier: Int, canBench: Bool) -> some View {
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
        let isDragging = draggingSlotID != nil
        let isMe = draggingSlotID == slot.id

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
                HStack(spacing: 4) {
                    Text(slot.subjectName)
                        .lineLimit(1)
                    if !isDragging {
                        Text("·")
                        Text("\(result.sessionCount) ses")
                        Text("·")
                        Text(String(format: "%.0fm", result.totalStudyMinutes))
                    }
                }
                .font(.gloucester(size: 11))
                .foregroundStyle(PigeonTheme.tertiaryText)
            }

            Spacer(minLength: 4)

            if isDragging && !isMe {
                Text("Tap to swap")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PigeonTheme.secondaryText.opacity(0.1))
                    .clipShape(Capsule())
            } else {
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

            if !isDragging {
                Button {
                    Haptics.light()
                    Task { await toggleRosterSlot(slot, targetMultiplier: canBench ? 1 : nextAvailableMultiplier()) }
                } label: {
                    Image(systemName: canBench ? "arrow.down.square" : "arrow.up.square")
                        .font(.system(size: 16))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(width: 30)
            } else {
                Color.clear.frame(width: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    /// Find the highest available multiplier for the next open starter slot.
    private func nextAvailableMultiplier() -> Int {
        let positions = slotPositions
        let activeSlots = rosterSlots.filter { $0.teamId == myTeam?.id && $0.isActive }

        // Count how many players are at each multiplier level
        var filled: [Int: Int] = [:]
        for slot in activeSlots {
            filled[slot.multiplier, default: 0] += 1
        }

        // Count how many positions exist at each multiplier level
        var available: [Int: Int] = [:]
        for mult in positions {
            available[mult, default: 0] += 1
        }

        // Find the highest multiplier with an open slot
        for mult in positions.sorted(by: >) {
            let filledCount = filled[mult] ?? 0
            let totalCount = available[mult] ?? 0
            if filledCount < totalCount {
                return mult
            }
        }
        return 1
    }

    private func toggleRosterSlot(_ slot: RosterSlotRow, targetMultiplier: Int) async {
        let newActive = !slot.isActive

        if newActive {
            let currentActive = rosterSlots.filter { $0.teamId == myTeam?.id && $0.isActive }.count
            guard currentActive < (league?.maxRosterSize ?? 8) else {
                Haptics.warning()
                return
            }
        }

        let newMultiplier = newActive ? targetMultiplier : 1

        do {
            try await SupabaseService.shared.updateRosterSlot(slotID: slot.id, isActive: newActive, multiplier: newMultiplier)
            if let idx = rosterSlots.firstIndex(where: { $0.id == slot.id }) {
                rosterSlots[idx].isActive = newActive
                rosterSlots[idx].multiplier = newMultiplier
            }
            Haptics.success()
            // Re-fetch to stay in sync with server
            if let leagueID = league?.id {
                rosterSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            }
        } catch {
            print("[LEAGUE] Toggle slot failed: \(error)")
            Haptics.error()
            // Revert local change on failure
            if let idx = rosterSlots.firstIndex(where: { $0.id == slot.id }) {
                rosterSlots[idx].isActive = !newActive
            }
        }
    }

    private func multiplierColor(_ mult: Int) -> Color {
        switch mult {
        case 3: return Color(red: 0.85, green: 0.55, blue: 0.15)
        case 2: return Color(red: 0.35, green: 0.55, blue: 0.75)
        default: return PigeonTheme.secondaryText
        }
    }

    // MARK: - Roster Drag Handlers

    /// Drop a dragged slot onto a starter position (swap or fill empty).
    private func handleRosterDrop(draggedID: UUID, toStarter index: Int) async {
        guard !rosterDragSaving else { return }
        rosterDragSaving = true
        defer {
            withAnimation(.easeInOut(duration: 0.15)) { draggingSlotID = nil }
            rosterDragSaving = false
        }

        guard let draggedSlot = rosterSlots.first(where: { $0.id == draggedID }) else { return }
        let positions = slotPositions
        guard index < positions.count else { return }
        let targetMult = positions[index]
        let activeList = orderedActiveSlots

        do {
            if let targetSlot = activeList[index] {
                // Swap
                let draggedMult = draggedSlot.multiplier
                let draggedWasActive = draggedSlot.isActive
                try await SupabaseService.shared.updateRosterSlot(
                    slotID: draggedID, isActive: true, multiplier: targetMult
                )
                try await SupabaseService.shared.updateRosterSlot(
                    slotID: targetSlot.id, isActive: draggedWasActive, multiplier: draggedWasActive ? draggedMult : 1
                )
            } else {
                // Fill empty slot
                try await SupabaseService.shared.updateRosterSlot(
                    slotID: draggedID, isActive: true, multiplier: targetMult
                )
            }
            Haptics.success()
            if let leagueID = league?.id {
                rosterSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            }
        } catch {
            print("[LEAGUE] Roster drag failed: \(error)")
            Haptics.error()
        }
    }

    /// Swap a dragged slot with a bench slot.
    private func handleRosterBenchSwap(draggedID: UUID, benchSlotID: UUID) async {
        guard !rosterDragSaving else { return }
        rosterDragSaving = true
        defer {
            withAnimation(.easeInOut(duration: 0.15)) { draggingSlotID = nil }
            rosterDragSaving = false
        }

        guard let draggedSlot = rosterSlots.first(where: { $0.id == draggedID }) else { return }
        let draggedMult = draggedSlot.multiplier
        let draggedWasActive = draggedSlot.isActive

        do {
            try await SupabaseService.shared.updateRosterSlot(
                slotID: draggedID, isActive: false, multiplier: 1
            )
            try await SupabaseService.shared.updateRosterSlot(
                slotID: benchSlotID, isActive: draggedWasActive, multiplier: draggedWasActive ? draggedMult : 1
            )
            Haptics.success()
            if let leagueID = league?.id {
                rosterSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            }
        } catch {
            print("[LEAGUE] Bench swap failed: \(error)")
            Haptics.error()
        }
    }

    /// Bench a dragged slot (no swap).
    private func handleRosterBench(slotID: UUID) async {
        guard !rosterDragSaving else { return }
        rosterDragSaving = true
        defer {
            withAnimation(.easeInOut(duration: 0.15)) { draggingSlotID = nil }
            rosterDragSaving = false
        }

        do {
            try await SupabaseService.shared.updateRosterSlot(slotID: slotID, isActive: false, multiplier: 1)
            Haptics.success()
            if let leagueID = league?.id {
                rosterSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            }
        } catch {
            print("[LEAGUE] Bench failed: \(error)")
            Haptics.error()
        }
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
                                    .fill(quotaGreen)
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

    // MARK: - Punishments Tab

    private struct WeeklyPunishmentData {
        var lowestScoringTeam: FantasyTeamRow?
        var lowestTeamScore: Double = 0
        var leastStudiedMember: UserRow?
        var leastStudiedUID: String?
        var leastStudyMinutes: Double = 0
    }

    private func computeWeeklyPunishmentData(week: Int) -> WeeklyPunishmentData {
        guard let league else { return WeeklyPunishmentData() }

        let calendar = Calendar(identifier: .iso8601)
        let weekStart = calendar.date(byAdding: .day, value: (week - 1) * 7, to: league.seasonStartDate) ?? league.seasonStartDate
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)?.addingTimeInterval(-1) ?? league.seasonStartDate

        let config = ScoringConfig.from(json: league.scoringConfigJson)

        // --- Lowest Scoring Team ---
        var teamScores: [(team: FantasyTeamRow, score: Double)] = []
        for team in teams {
            let teamSlots = rosterSlots.filter { $0.teamId == team.id && $0.isActive }
            var total: Double = 0
            for slot in teamSlots {
                let result = LeagueScoringEngine.calculateScore(
                    playerUID: slot.playerUid,
                    subject: slot.subjectName,
                    timelapses: localTimelapses,
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    config: config,
                    multiplier: slot.multiplier
                )
                total += result.multipliedScore
            }
            teamScores.append((team: team, score: total))
        }
        let lowestTeam = teamScores.min(by: { $0.score < $1.score })

        // --- Least Studied Person ---
        var memberMinutes: [(uid: String, minutes: Double)] = []
        for memberUID in league.memberUids {
            let memberUIDUpper = memberUID.uppercased()
            let relevantTimelapses = localTimelapses.filter { t in
                t.authorID.uppercased() == memberUIDUpper
                    && t.createdAt >= weekStart
                    && t.createdAt <= weekEnd
            }
            let totalMinutes = relevantTimelapses.reduce(0.0) { sum, t in
                sum + Double(t.durationSeconds) / 60.0
            }
            memberMinutes.append((uid: memberUID, minutes: totalMinutes))
        }
        let leastStudied = memberMinutes.min(by: { $0.minutes < $1.minutes })

        var result = WeeklyPunishmentData()
        if let lowestTeam {
            result.lowestScoringTeam = lowestTeam.team
            result.lowestTeamScore = lowestTeam.score
        }
        if let leastStudied {
            let profile = memberProfiles[leastStudied.uid]
                ?? memberProfiles[leastStudied.uid.uppercased()]
                ?? memberProfiles[leastStudied.uid.lowercased()]
            result.leastStudiedMember = profile
            result.leastStudiedUID = leastStudied.uid
            result.leastStudyMinutes = leastStudied.minutes
        }
        return result
    }

    // MARK: - Punishments Tab (Pool + Weekly Voting)

    /// How many votes the current user has already spent on pool items this week.
    private func poolVotesUsedThisWeek() -> Int {
        let suffix = ":\(displayedWeek)"
        return poolPunishments.reduce(0) { total, p in
            total + p.approvalVotes.filter { $0.hasPrefix(uid) && $0.hasSuffix(suffix) }.count
        }
    }

    /// Pool items: status == "pool"
    private var poolPunishments: [PunishmentRow] {
        punishments.filter { $0.status == "pool" }
    }

    /// Chosen punishments for the displayed week
    private var chosenPunishmentsForWeek: [PunishmentRow] {
        punishments.filter { $0.status == "chosen" && $0.weekNumber == displayedWeek }
    }

    /// Vote count for a pool item in the displayed week
    private func weekVoteCount(for punishment: PunishmentRow) -> Int {
        let suffix = ":\(displayedWeek)"
        return punishment.approvalVotes.filter { $0.hasSuffix(suffix) }.count
    }

    /// Whether the current user has already voted for this pool item this week
    private func hasVotedForPool(_ punishment: PunishmentRow) -> Bool {
        punishment.approvalVotes.contains("\(uid):\(displayedWeek)")
    }

    /// Who submitted this pool punishment (stored in `reason` field for pool items)
    private func poolSubmitterName(_ punishment: PunishmentRow) -> String {
        memberProfiles[punishment.reason]?.displayName
            ?? memberProfiles[punishment.reason.uppercased()]?.displayName
            ?? "Someone"
    }

    private var punishmentsTab: some View {
        VStack(spacing: 12) {
            // Week selector
            HStack(spacing: 16) {
                Button {
                    Haptics.light()
                    withAnimation { selectedWeek = max(1, displayedWeek - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(displayedWeek > 1 ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                }
                .disabled(displayedWeek <= 1)

                VStack(spacing: 2) {
                    Text("WEEK \(displayedWeek)")
                        .font(.gloucester(size: 16))
                        .foregroundStyle(PigeonTheme.primaryText)
                    if displayedWeek == currentWeek {
                        Text("current")
                            .font(.gloucester(size: 10))
                            .foregroundStyle(quotaGreen)
                    }
                }

                Button {
                    Haptics.light()
                    withAnimation { selectedWeek = min(maxWeek, displayedWeek + 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(displayedWeek < maxWeek ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                }
                .disabled(displayedWeek >= maxWeek)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            if displayedWeek != currentWeek {
                Button {
                    Haptics.light()
                    withAnimation { selectedWeek = nil }
                } label: {
                    Text("Go to Current Week")
                        .font(.gloucester(size: 12))
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }

            // Auto-detection: who lost this week
            punishmentAutoDetection

            // Chosen punishment for this week (if any)
            if !chosenPunishmentsForWeek.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("THIS WEEK'S PUNISHMENT")
                        .pigeonSectionTitle()
                    ForEach(chosenPunishmentsForWeek, id: \.id) { p in
                        chosenPunishmentCard(p)
                    }
                }
            }

            // Punishment Pool
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PUNISHMENT POOL")
                        .pigeonSectionTitle()
                    Spacer()
                    let used = poolVotesUsedThisWeek()
                    Text("\(used)/\(votesPerMember) votes used")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(used >= votesPerMember ? PigeonTheme.destructive : PigeonTheme.tertiaryText)
                }

                if poolPunishments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("No punishments in the pool yet")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("Add ideas that members can vote on each week")
                            .font(.gloucester(size: 11))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Sort by vote count for the displayed week (most votes first)
                    let sorted = poolPunishments.sorted { weekVoteCount(for: $0) > weekVoteCount(for: $1) }
                    ForEach(sorted, id: \.id) { punishment in
                        poolPunishmentCard(punishment)
                    }
                }

                // Add to pool button — any member can add
                Button {
                    Haptics.medium()
                    showProposePunishment = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.gloucester(size: 16))
                        Text("Add Punishment Idea")
                            .font(.gloucester(size: 14))
                    }
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .pigeonGlassSurface(cornerRadius: 12)
                }
            }
        }
        .sheet(isPresented: $showProposePunishment) {
            AddPunishmentToPoolSheet(leagueID: leagueID) {
                Task { await loadPunishments() }
            }
        }
    }

    private var punishmentAutoDetection: some View {
        let weekData = computeWeeklyPunishmentData(week: displayedWeek)

        return VStack(spacing: 10) {
            // Lowest Scoring Team card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .foregroundStyle(PigeonTheme.destructive)
                    Text("LOWEST SCORING TEAM")
                        .pigeonSectionTitle()
                    Spacer()
                }

                if let loser = weekData.lowestScoringTeam {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loser.teamName)
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Text(memberProfiles[loser.ownerUid]?.displayName ?? "")
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        Spacer()
                        Text(String(format: "%.1f pts", weekData.lowestTeamScore))
                            .font(.gloucester(size: 20))
                            .foregroundStyle(PigeonTheme.destructive)
                    }
                } else {
                    Text("No scores available yet")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            .padding(16)
            .pigeonGlassSurface(cornerRadius: 14)

            // Least Studied Person card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.15))
                    Text("LEAST STUDIED PERSON")
                        .pigeonSectionTitle()
                    Spacer()
                }

                if let slacker = weekData.leastStudiedMember {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slacker.displayName)
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let h = Int(weekData.leastStudyMinutes) / 60
                            let m = Int(weekData.leastStudyMinutes) % 60
                            Text("\(h)h \(m)m")
                                .font(.gloucester(size: 20))
                                .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.15))
                            Text("studied")
                                .font(.gloucester(size: 10))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }
                } else {
                    Text("No study data available yet")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            .padding(16)
            .pigeonGlassSurface(cornerRadius: 14)
        }
    }

    /// A pool punishment card with vote button and count.
    private func poolPunishmentCard(_ punishment: PunishmentRow) -> some View {
        let votes = weekVoteCount(for: punishment)
        let voted = hasVotedForPool(punishment)
        let votesRemaining = votesPerMember - poolVotesUsedThisWeek()
        let canVote = !voted && votesRemaining > 0
        let submitter = poolSubmitterName(punishment)
        let canDelete = punishment.reason == uid || isCommissioner

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Vote button
                Button {
                    Haptics.medium()
                    if voted {
                        Task { await unvotePool(punishment) }
                    } else if canVote {
                        Task { await votePool(punishment) }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: voted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(voted ? Color(red: 0.85, green: 0.55, blue: 0.15) : PigeonTheme.tertiaryText)
                        Text("\(votes)")
                            .font(.gloucester(size: 14))
                            .foregroundStyle(voted ? Color(red: 0.85, green: 0.55, blue: 0.15) : PigeonTheme.primaryText)
                    }
                    .frame(width: 36)
                }
                .disabled(!voted && !canVote)

                VStack(alignment: .leading, spacing: 4) {
                    Text(punishment.punishmentDescription)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(3)

                    Text("added by \(submitter)")
                        .font(.gloucester(size: 10))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }

                Spacer()

                if canDelete {
                    Button {
                        Haptics.light()
                        Task { await deletePool(punishment) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
            }
        }
        .padding(12)
        .pigeonGlassSurface(cornerRadius: 12)
    }

    /// A card for a punishment that has been chosen for a specific week.
    private func chosenPunishmentCard(_ punishment: PunishmentRow) -> some View {
        let targetName = memberProfiles[punishment.targetUid]?.displayName
            ?? memberProfiles[punishment.targetUid.uppercased()]?.displayName
            ?? "Unknown"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PigeonTheme.destructive)
                Text("CHOSEN")
                    .font(.gloucester(size: 12))
                    .foregroundStyle(PigeonTheme.destructive)
                Spacer()
            }

            Text(punishment.punishmentDescription)
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.primaryText)

            HStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Text(targetName)
                    .font(.gloucester(size: 13))
                    .foregroundStyle(PigeonTheme.secondaryText)
            }
        }
        .padding(16)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    private func votePool(_ punishment: PunishmentRow) async {
        do {
            try await SupabaseService.shared.votePoolPunishment(
                punishmentID: punishment.id, voterUID: uid, week: displayedWeek
            )
            Haptics.success()
            await loadPunishments()
        } catch {
            print("[PUNISH] Pool vote failed: \(error)")
        }
    }

    private func unvotePool(_ punishment: PunishmentRow) async {
        do {
            try await SupabaseService.shared.unvotePoolPunishment(
                punishmentID: punishment.id, voterUID: uid, week: displayedWeek
            )
            Haptics.light()
            await loadPunishments()
        } catch {
            print("[PUNISH] Pool unvote failed: \(error)")
        }
    }

    private func deletePool(_ punishment: PunishmentRow) async {
        do {
            try await SupabaseService.shared.deletePoolPunishment(punishmentID: punishment.id)
            Haptics.success()
            await loadPunishments()
        } catch {
            print("[PUNISH] Pool delete failed: \(error)")
        }
    }

    private func loadPunishments() async {
        do {
            punishments = try await SupabaseService.shared.fetchPunishments(leagueID: leagueID)
        } catch {
            print("[PUNISH] Load failed: \(error)")
        }
    }

    // MARK: - More Tab

    private var moreTab: some View {
        VStack(spacing: 10) {
            moreButton(icon: "list.clipboard.fill", title: "Draft", subtitle: "Snake draft board and picks") {
                withAnimation(.easeInOut(duration: 0.2)) { dashTab = 4 }
            }
            moreRow(icon: "arrow.triangle.2.circlepath", title: "Trades", subtitle: "Propose and manage trades") {
                TradeView(leagueID: leagueID)
            }
            moreRow(icon: "person.badge.plus", title: "Free Agents", subtitle: "Pick up unclaimed players") {
                FreeAgentView(leagueID: leagueID)
            }
            moreRow(icon: "chart.bar.fill", title: "Manager Ratings", subtitle: "How managers stack up") {
                ManagerRatingView(leagueID: leagueID)
            }
            moreRow(icon: "sportscourt", title: "Playoffs", subtitle: "Bracket and seeding") {
                PlayoffBracketView(leagueID: leagueID)
            }
        }
    }

    private func moreButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private let tabItems: [(id: Int, label: String)] = [
        (0, "Home"),
        (1, "Matchups"),
        (2, "Standings"),
        (3, "Roster"),
        (5, "Punishments"),
        (6, "More"),
    ]

    private var leagueTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(tabItems, id: \.id) { item in
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { dashTab = item.id }
                        } label: {
                            VStack(spacing: 6) {
                                Text(item.label)
                                    .font(.gloucester(size: 13))
                                    .fontWeight(dashTab == item.id ? .semibold : .regular)
                                    .foregroundStyle(dashTab == item.id ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(dashTab == item.id ? PigeonTheme.primaryText : Color.clear)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: dashTab == item.id ? "leagueTab" : "leagueTab_\(item.id)", in: tabNS)
                            }
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(PigeonTheme.separator.opacity(0.5))
                    .frame(height: 0.5)
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
                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.15))
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

    // MARK: - Data Loading

    private func loadData() async {
        do {
            async let leagueResult = SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            async let teamsResult = SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            async let rosterResult = SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            async let matchupsResult = SupabaseService.shared.fetchMatchups(leagueID: leagueID)
            async let ratingsResult = SupabaseService.shared.fetchManagerRatings(leagueID: leagueID)
            async let punishmentsResult = SupabaseService.shared.fetchPunishments(leagueID: leagueID)

            league = try await leagueResult
            teams = try await teamsResult
            rosterSlots = try await rosterResult
            matchups = try await matchupsResult
            managerRatings = try await ratingsResult
            punishments = try await punishmentsResult

            myTeam = teams.first(where: { $0.ownerUid == uid })
            // Show current week matchup, or fall back to latest matchup for my team
            let myMatchups = matchups.filter { $0.team1Id == myTeam?.id || $0.team2Id == myTeam?.id }
            currentMatchup = myMatchups.first(where: { $0.weekNumber == currentWeek })
                ?? myMatchups.sorted(by: { $0.weekNumber > $1.weekNumber }).first

            if let league {
                let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
                for profile in profiles {
                    // Store by both original and uppercased key for case-insensitive lookup
                    let key = profile.uid.uuidString
                    memberProfiles[key] = profile
                    memberProfiles[key.uppercased()] = profile
                    memberProfiles[key.lowercased()] = profile
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
