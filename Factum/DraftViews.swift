//
//  DraftViews.swift
//  Pigeon
//
//  Draft lobby, live draft room, and draft results
//

import SwiftUI
import SwiftData

// MARK: - Draft Lobby

struct DraftLobbyView: View {
    let leagueID: UUID
    @Query private var users: [UserProfile]

    @State private var league: FantasyLeagueRow?
    @State private var teams: [FantasyTeamRow] = []
    @State private var draftPool: [(uid: String, displayName: String, subject: String)] = []
    @State private var draftOrder: [String] = []
    @State private var isLoading = true
    @State private var isStarting = false
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID
    private var isCommissioner: Bool { league?.commissionerUid == uid }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Draft Setup")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    // Draft Order
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("DRAFT ORDER")
                                .pigeonSectionTitle()
                            Spacer()
                            if isCommissioner {
                                Button {
                                    Haptics.light()
                                    draftOrder = teams.map { $0.ownerUid }.shuffled()
                                } label: {
                                    Label("Randomize", systemImage: "shuffle")
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                }
                            }
                        }

                        ForEach(Array(draftOrder.enumerated()), id: \.offset) { index, ownerUID in
                            let teamName = teams.first(where: { $0.ownerUid == ownerUID })?.teamName ?? "Unknown"
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                                    .frame(width: 24)
                                Text(teamName)
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                            }
                            .padding(12)
                            .pigeonGlassSurface(cornerRadius: 10)
                        }
                    }
                    .staggeredAppear(index: 1, appeared: appeared)

                    // Available Players Preview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DRAFT POOL (\(draftPool.count) PLAYERS)")
                            .pigeonSectionTitle()

                        ForEach(Array(draftPool.prefix(20).enumerated()), id: \.offset) { _, player in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(PigeonTheme.accent)
                                        .frame(width: 32, height: 32)
                                    Text(String(player.displayName.prefix(1)))
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(player.displayName)
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    Text(player.subject)
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .pigeonGlassSurface(cornerRadius: 10)
                        }

                        if draftPool.count > 20 {
                            Text("and \(draftPool.count - 20) more...")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }
                    .staggeredAppear(index: 2, appeared: appeared)

                    // Start Draft Button
                    if isCommissioner {
                        Button {
                            Haptics.medium()
                            Task { await startDraft() }
                        } label: {
                            if isStarting {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Start Draft").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PigeonButtonStyle())
                        .disabled(teams.count < 2 || isStarting)
                        .staggeredAppear(index: 3, appeared: appeared)
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

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            draftOrder = teams.map { $0.ownerUid }

            // Build draft pool
            guard let league else { return }
            let memberSubjects = try await SupabaseService.shared.fetchMemberSubjects(memberUIDs: league.memberUids)
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.uid.uuidString, $0.displayName) })

            draftPool = memberSubjects.flatMap { item in
                item.subjects.map { subject in
                    (uid: item.uid, displayName: profileMap[item.uid] ?? "Unknown", subject: subject)
                }
            }
        } catch {
            print("[DRAFT] Load failed: \(error)")
        }
        isLoading = false
    }

    private func startDraft() async {
        isStarting = true
        // Build snake draft order
        let totalRounds = (league?.maxRosterSize ?? 8) + (league?.benchSize ?? 3)
        var fullOrder: [String] = []
        for round in 0..<totalRounds {
            if round % 2 == 0 {
                fullOrder.append(contentsOf: draftOrder)
            } else {
                fullOrder.append(contentsOf: draftOrder.reversed())
            }
        }

        do {
            try await SupabaseService.shared.startDraft(leagueID: leagueID, draftOrder: fullOrder)
            league?.draftStatus = "in_progress"
            Haptics.success()
        } catch {
            print("[DRAFT] Start failed: \(error)")
            Haptics.error()
        }
        isStarting = false
    }
}

// MARK: - Draft Room

struct DraftRoomView: View {
    let leagueID: UUID
    @Query private var localTimelapses: [StudyTimelapse]

    @State private var league: FantasyLeagueRow?
    @State private var teams: [FantasyTeamRow] = []
    @State private var picks: [DraftPickRow] = []
    @State private var draftPool: [(uid: String, displayName: String, subject: String)] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var isMakingPick = false
    @State private var appeared = false
    @State private var pollTimer: Timer?
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID

    private var currentPickIndex: Int { league?.currentDraftPickIndex ?? 0 }
    private var draftOrder: [String] { league?.draftOrder ?? [] }
    private var isMyTurn: Bool {
        guard currentPickIndex < draftOrder.count else { return false }
        return draftOrder[currentPickIndex] == uid
    }
    private var currentPickerUID: String? {
        guard currentPickIndex < draftOrder.count else { return nil }
        return draftOrder[currentPickIndex]
    }
    private var currentRound: Int { (currentPickIndex / max(1, teams.count)) + 1 }
    private var pickInRound: Int { (currentPickIndex % max(1, teams.count)) + 1 }

    // Filter out already-drafted combos
    private var availablePlayers: [(uid: String, displayName: String, subject: String)] {
        let drafted = Set(picks.map { "\($0.playerUid)|\($0.subjectName)" })
        return draftPool.filter { !drafted.contains("\($0.uid)|\($0.subject)") }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Draft Room")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    if league?.draftStatus == "completed" {
                        Text("COMPLETE")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if league?.draftStatus == "completed" {
                    draftCompleteView
                } else {
                    // Current Pick Info
                    VStack(spacing: 8) {
                        Text("Round \(currentRound), Pick \(pickInRound)")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)

                        if isMyTurn {
                            Text("YOUR PICK")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        } else if let pickerUID = currentPickerUID {
                            let name = memberProfiles[pickerUID]?.displayName ?? "..."
                            Text("\(name) is picking")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .pigeonGlassSurface(cornerRadius: 14)
                    .staggeredAppear(index: 1, appeared: appeared)

                    // Recent Picks
                    if !picks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RECENT PICKS")
                                .pigeonSectionTitle()
                            ForEach(picks.suffix(5).reversed(), id: \.id) { pick in
                                let teamName = teams.first(where: { $0.id == pick.teamId })?.teamName ?? "Team"
                                let playerName = memberProfiles[pick.playerUid]?.displayName ?? "Player"
                                HStack(spacing: 10) {
                                    Text("#\(pick.pickNumber)")
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(teamName)")
                                            .font(PigeonTheme.smallFont)
                                            .foregroundStyle(PigeonTheme.secondaryText)
                                        Text("\(playerName) — \(pick.subjectName)")
                                            .font(PigeonTheme.captionFont)
                                            .foregroundStyle(PigeonTheme.primaryText)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .pigeonGlassSurface(cornerRadius: 10)
                            }
                        }
                        .staggeredAppear(index: 2, appeared: appeared)
                    }

                    // Available Players (only show if it's my turn)
                    if isMyTurn {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AVAILABLE PLAYERS")
                                .pigeonSectionTitle()
                            ForEach(Array(availablePlayers.enumerated()), id: \.offset) { _, player in
                                Button {
                                    Haptics.medium()
                                    Task { await makePick(playerUID: player.uid, subject: player.subject) }
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(PigeonTheme.accent)
                                                .frame(width: 36, height: 36)
                                            Text(String(player.displayName.prefix(1)))
                                                .font(PigeonTheme.captionFont)
                                                .foregroundStyle(PigeonTheme.primaryText)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(player.displayName)
                                                .font(PigeonTheme.captionFont)
                                                .foregroundStyle(PigeonTheme.primaryText)
                                            Text(player.subject)
                                                .font(PigeonTheme.smallFont)
                                                .foregroundStyle(PigeonTheme.secondaryText)
                                        }
                                        Spacer()
                                        if isMakingPick {
                                            ProgressView()
                                        } else {
                                            Text("Draft")
                                                .font(PigeonTheme.smallFont)
                                                .foregroundStyle(PigeonTheme.background)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(PigeonTheme.primaryText)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(12)
                                    .pigeonGlassSurface(cornerRadius: 12)
                                }
                                .buttonStyle(.plain)
                                .disabled(isMakingPick)
                            }
                        }
                        .staggeredAppear(index: 3, appeared: appeared)
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
        .onAppear {
            withAnimation { appeared = true }
            startPolling()
        }
        .onDisappear { stopPolling() }
        .task { await loadData() }
    }

    private var draftCompleteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Draft Complete!")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Text("\(picks.count) players drafted")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(.top, 40)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await refreshDraftState() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshDraftState() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            picks = try await SupabaseService.shared.fetchDraftPicks(leagueID: leagueID)

            // Auto-complete draft if all picks made
            if let league, currentPickIndex >= league.draftOrder.count, league.draftStatus != "completed" {
                try await SupabaseService.shared.completeDraft(leagueID: leagueID)
                self.league?.draftStatus = "completed"
                stopPolling()
            }
        } catch {
            print("[DRAFT] Poll failed: \(error)")
        }
    }

    // MARK: - Make Pick

    private func makePick(playerUID: String, subject: String) async {
        guard let myTeam = teams.first(where: { $0.ownerUid == uid }) else { return }
        isMakingPick = true

        // Determine which multiplier slot this pick fills for the team.
        // Count how many picks this team already has, then look up the
        // multiplier from the league's slot config.
        let myPickCount = picks.filter { $0.teamId == myTeam.id }.count
        let slotConfig = league?.slotMultipliers ?? []
        let multiplier = myPickCount < slotConfig.count ? slotConfig[myPickCount] : 1

        do {
            try await SupabaseService.shared.makeDraftPick(
                leagueID: leagueID,
                teamID: myTeam.id,
                playerUID: playerUID,
                subjectName: subject,
                round: currentRound,
                pick: currentPickIndex + 1,
                multiplier: multiplier
            )
            Haptics.success()
            await refreshDraftState()
        } catch {
            print("[DRAFT] Pick failed: \(error)")
            Haptics.error()
        }
        isMakingPick = false
    }

    // MARK: - Load Data

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            picks = try await SupabaseService.shared.fetchDraftPicks(leagueID: leagueID)

            guard let league else { return }
            let memberSubjects = try await SupabaseService.shared.fetchMemberSubjects(memberUIDs: league.memberUids)
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
            for p in profiles {
                memberProfiles[p.uid.uuidString] = p
            }
            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.uid.uuidString, $0.displayName) })
            draftPool = memberSubjects.flatMap { item in
                item.subjects.map { subject in
                    (uid: item.uid, displayName: profileMap[item.uid] ?? "Unknown", subject: subject)
                }
            }
        } catch {
            print("[DRAFT] Load failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Draft Results

struct DraftResultsView: View {
    let leagueID: UUID

    @State private var picks: [DraftPickRow] = []
    @State private var teams: [FantasyTeamRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    private var rounds: [[DraftPickRow]] {
        Dictionary(grouping: picks) { $0.roundNumber }
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
                    Text("Draft Results")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    ForEach(Array(rounds.enumerated()), id: \.offset) { roundIndex, roundPicks in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROUND \(roundIndex + 1)")
                                .pigeonSectionTitle()
                            ForEach(roundPicks, id: \.id) { pick in
                                let teamName = teams.first(where: { $0.id == pick.teamId })?.teamName ?? "Team"
                                let playerName = memberProfiles[pick.playerUid]?.displayName ?? "Player"
                                HStack(spacing: 10) {
                                    Text("#\(pick.pickNumber)")
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(teamName)
                                            .font(PigeonTheme.smallFont)
                                            .foregroundStyle(PigeonTheme.secondaryText)
                                        Text("\(playerName) — \(pick.subjectName)")
                                            .font(PigeonTheme.captionFont)
                                            .foregroundStyle(PigeonTheme.primaryText)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .pigeonGlassSurface(cornerRadius: 10)
                            }
                        }
                        .staggeredAppear(index: roundIndex + 1, appeared: appeared)
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

    private func loadData() async {
        do {
            picks = try await SupabaseService.shared.fetchDraftPicks(leagueID: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            let league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            if let league {
                let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
                for p in profiles { memberProfiles[p.uid.uuidString] = p }
            }
        } catch {
            print("[DRAFT] Results load failed: \(error)")
        }
        isLoading = false
    }
}
