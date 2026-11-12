//
//  LeagueSettingsView.swift
//  Pigeon
//
//  Commissioner controls for a fantasy league
//

import SwiftUI
import SwiftData

struct LeagueSettingsView: View {
    let league: FantasyLeagueRow
    var onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var localTimelapses: [StudyTimelapse]

    @State private var name: String
    @State private var description: String
    @State private var seasonEndDate: Date
    @State private var playoffTeams: Int
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var showGenerateConfirm = false
    @State private var showFinalizeConfirm = false
    @State private var isGenerating = false
    @State private var isFinalizing = false
    @State private var teams: [FantasyTeamRow] = []
    @State private var matchups: [WeeklyMatchupRow] = []
    @State private var actionMessage: String?

    private var currentWeek: Int {
        LeagueScoringEngine.weekNumber(for: Date(), seasonStart: league.seasonStartDate)
    }

    private var hasMatchups: Bool {
        !matchups.isEmpty
    }

    private var currentWeekMatchups: [WeeklyMatchupRow] {
        matchups.filter { $0.weekNumber == currentWeek && $0.winnerTeamId == nil }
    }

    init(league: FantasyLeagueRow, onUpdated: @escaping () -> Void) {
        self.league = league
        self.onUpdated = onUpdated
        _name = State(initialValue: league.name)
        _description = State(initialValue: league.description)
        _seasonEndDate = State(initialValue: league.seasonEndDate)
        _playoffTeams = State(initialValue: league.playoffTeamCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Commissioner Actions
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COMMISSIONER ACTIONS")
                            .pigeonSectionTitle()

                        // Generate Matchups
                        Button {
                            if hasMatchups {
                                showGenerateConfirm = true
                            } else {
                                Task { await generateMatchups() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 18))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Generate Matchups")
                                        .font(PigeonTheme.captionFont)
                                    Text(hasMatchups ? "Regenerate schedule (\(matchups.count) existing)" : "Create round-robin schedule")
                                        .font(.gloucester(size: 11))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                                Spacer()
                                if isGenerating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                            }
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                        }
                        .disabled(isGenerating || teams.count < 2)

                        // Finalize Current Week
                        Button {
                            showFinalizeConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 18))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Finalize Week \(currentWeek)")
                                        .font(PigeonTheme.captionFont)
                                    Text("Lock scores and update records")
                                        .font(.gloucester(size: 11))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                                Spacer()
                                if isFinalizing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                            }
                            .foregroundStyle(currentWeekMatchups.isEmpty ? PigeonTheme.tertiaryText : PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                        }
                        .disabled(isFinalizing || currentWeekMatchups.isEmpty)

                        if let actionMessage {
                            Text(actionMessage)
                                .font(.gloucester(size: 12))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAGUE NAME")
                            .pigeonSectionTitle()
                        TextField("League Name", text: $name)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION")
                            .pigeonSectionTitle()
                        TextField("Description", text: $description)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("SEASON")
                            .pigeonSectionTitle()

                        HStack {
                            Text("Season End")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            DatePicker("", selection: $seasonEndDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Playoff Teams")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Stepper("\(playoffTeams)", value: $playoffTeams, in: 2...8)
                                .font(PigeonTheme.bodyFont)
                                .frame(width: 140)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // League Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAGUE INFO")
                            .pigeonSectionTitle()
                        settingsInfoRow("Members", value: "\(league.memberUids.count)")
                        settingsInfoRow("Roster Size", value: "\(league.maxRosterSize) + \(league.benchSize) bench")
                        settingsInfoRow("Draft Status", value: league.draftStatus.capitalized)
                        settingsInfoRow("Season Week", value: "Week \(currentWeek)")
                        settingsInfoRow("Total Matchups", value: "\(matchups.count)")
                    }

                    // Save
                    Button {
                        Haptics.medium()
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Save Changes").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PigeonButtonStyle())
                    .disabled(isSaving)

                    // Delete League
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete League")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.destructive)
                    }
                    .padding(.top, 16)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationTitle("League Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
            .task { await loadSettingsData() }
            .alert("Delete League?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task { await deleteLeague() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the league and all associated data. This cannot be undone.")
            }
            .alert("Regenerate Matchups?", isPresented: $showGenerateConfirm) {
                Button("Regenerate", role: .destructive) {
                    Task { await generateMatchups() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all unfinalized matchups and create a new round-robin schedule. Finalized results are preserved.")
            }
            .alert("Finalize Week \(currentWeek)?", isPresented: $showFinalizeConfirm) {
                Button("Finalize") {
                    Task { await finalizeCurrentWeek() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will lock the current week's scores, update win/loss records, and adjust manager ratings. This cannot be undone.")
            }
        }
    }

    private func settingsInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Spacer()
            Text(value)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
    }

    // MARK: - Data Loading

    private func loadSettingsData() async {
        do {
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: league.id)
            matchups = try await SupabaseService.shared.fetchMatchups(leagueID: league.id)
        } catch {
            print("[SETTINGS] Load failed: \(error)")
        }
    }

    // MARK: - Generate Matchups

    private func generateMatchups() async {
        isGenerating = true
        actionMessage = nil
        do {
            // Delete unfinalized matchups first
            try await SupabaseService.shared.deleteUnfinalizedMatchups(leagueID: league.id)

            let generated = try await SupabaseService.shared.generateSeasonMatchups(league: league, teams: teams)
            matchups = try await SupabaseService.shared.fetchMatchups(leagueID: league.id)
            actionMessage = "Generated \(generated.count) matchups"
            Haptics.success()
            onUpdated()
        } catch {
            print("[SETTINGS] Generate matchups failed: \(error)")
            actionMessage = "Failed to generate matchups"
            Haptics.error()
        }
        isGenerating = false
    }

    // MARK: - Finalize Week

    private func finalizeCurrentWeek() async {
        isFinalizing = true
        actionMessage = nil
        do {
            let weekMatchups = matchups.filter { $0.weekNumber == currentWeek && $0.winnerTeamId == nil }
            let allSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: league.id)
            let config = ScoringConfig.from(json: league.scoringConfigJson)
            var ratings = try await SupabaseService.shared.fetchManagerRatings(leagueID: league.id)

            for matchup in weekMatchups {
                let t1Slots = allSlots.filter { $0.teamId == matchup.team1Id }
                let t2Slots = allSlots.filter { $0.teamId == matchup.team2Id }

                // Compute scores from local timelapses
                let t1Score = t1Slots.filter { $0.isActive }.reduce(0.0) { total, slot in
                    total + LeagueScoringEngine.calculateScore(
                        playerUID: slot.playerUid, subject: slot.subjectName,
                        timelapses: localTimelapses,
                        weekStart: matchup.weekStartDate, weekEnd: matchup.weekEndDate,
                        config: config, multiplier: slot.multiplier
                    ).multipliedScore
                }
                let t2Score = t2Slots.filter { $0.isActive }.reduce(0.0) { total, slot in
                    total + LeagueScoringEngine.calculateScore(
                        playerUID: slot.playerUid, subject: slot.subjectName,
                        timelapses: localTimelapses,
                        weekStart: matchup.weekStartDate, weekEnd: matchup.weekEndDate,
                        config: config, multiplier: slot.multiplier
                    ).multipliedScore
                }

                let winner: UUID?
                if matchup.isBye {
                    winner = matchup.team1Id
                } else if t1Score > t2Score {
                    winner = matchup.team1Id
                } else if t2Score > t1Score {
                    winner = matchup.team2Id
                } else {
                    winner = nil // tie
                }

                // Update matchup scores
                try await SupabaseService.shared.updateMatchupResult(
                    matchupID: matchup.id, team1Score: t1Score, team2Score: t2Score, winnerTeamID: winner
                )

                // Update team records
                if !matchup.isBye {
                    if var t1 = teams.first(where: { $0.id == matchup.team1Id }) {
                        t1.totalPointsFor += t1Score
                        t1.totalPointsAgainst += t2Score
                        if winner == t1.id { t1.wins += 1 }
                        else if winner == nil { t1.ties += 1 }
                        else { t1.losses += 1 }
                        try await SupabaseService.shared.updateTeamRecord(t1)
                    }
                    if var t2 = teams.first(where: { $0.id == matchup.team2Id }) {
                        t2.totalPointsFor += t2Score
                        t2.totalPointsAgainst += t1Score
                        if winner == t2.id { t2.wins += 1 }
                        else if winner == nil { t2.ties += 1 }
                        else { t2.losses += 1 }
                        try await SupabaseService.shared.updateTeamRecord(t2)
                    }
                }

                // Update manager ratings (Elo)
                if !matchup.isBye {
                    let t1Owner = teams.first(where: { $0.id == matchup.team1Id })?.ownerUid
                    let t2Owner = teams.first(where: { $0.id == matchup.team2Id })?.ownerUid
                    if let t1Owner, let t2Owner,
                       var r1 = ratings.first(where: { $0.managerUid == t1Owner }),
                       var r2 = ratings.first(where: { $0.managerUid == t2Owner }) {
                        let newR1 = ManagerRatingEngine.adjustedRating(currentRating: r1.overallRating, opponentRating: r2.overallRating, myScore: t1Score, oppScore: t2Score)
                        let newR2 = ManagerRatingEngine.adjustedRating(currentRating: r2.overallRating, opponentRating: r1.overallRating, myScore: t2Score, oppScore: t1Score)
                        r1.overallRating = newR1
                        r1.updatedAt = Date()
                        r2.overallRating = newR2
                        r2.updatedAt = Date()
                        try await SupabaseService.shared.upsertManagerRating(r1)
                        try await SupabaseService.shared.upsertManagerRating(r2)
                        if let idx1 = ratings.firstIndex(where: { $0.id == r1.id }) { ratings[idx1] = r1 }
                        if let idx2 = ratings.firstIndex(where: { $0.id == r2.id }) { ratings[idx2] = r2 }
                    }
                }
            }

            // Reload data
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: league.id)
            matchups = try await SupabaseService.shared.fetchMatchups(leagueID: league.id)
            actionMessage = "Week \(currentWeek) finalized"
            Haptics.success()
            onUpdated()
        } catch {
            print("[SETTINGS] Finalize week failed: \(error)")
            actionMessage = "Failed to finalize week"
            Haptics.error()
        }
        isFinalizing = false
    }

    private func saveChanges() async {
        isSaving = true
        var updated = league
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.description = description
        updated.seasonEndDate = seasonEndDate
        updated.playoffTeamCount = playoffTeams
        do {
            try await SupabaseService.shared.updateFantasyLeague(updated)
            Haptics.success()
            onUpdated()
            dismiss()
        } catch {
            print("[LEAGUE] Settings save failed: \(error)")
            Haptics.error()
        }
        isSaving = false
    }

    private func deleteLeague() async {
        do {
            try await SupabaseService.shared.deleteFantasyLeague(id: league.id)
            Haptics.success()
            onUpdated()
            dismiss()
        } catch {
            print("[LEAGUE] Delete failed: \(error)")
            Haptics.error()
        }
    }
}
