//
//  LeagueSupabaseService.swift
//  Pigeon
//
//  Supabase CRUD operations for fantasy study leagues
//

import Foundation
import Supabase

extension SupabaseService {

    // MARK: - Leagues

    func createFantasyLeague(_ league: FantasyLeague) async throws {
        let row = FantasyLeagueRow(
            id: league.id,
            name: league.name,
            commissionerUid: league.commissionerUID,
            memberUids: league.memberUIDs,
            seasonStartDate: league.seasonStartDate,
            seasonEndDate: league.seasonEndDate,
            createdAt: league.createdAt,
            maxRosterSize: league.maxRosterSize,
            benchSize: league.benchSize,
            draftStatus: league.draftStatus,
            draftOrder: league.draftOrder,
            currentDraftPickIndex: league.currentDraftPickIndex,
            playoffTeamCount: league.playoffTeamCount,
            weeklyMatchupsJson: league.weeklyMatchupsJSON,
            scoringConfigJson: league.scoringConfigJSON,
            slotConfigJson: league.slotConfigJSON,
            iconName: league.iconName,
            description: league.leagueDescription,
            draftSecondsPerPick: league.draftSecondsPerPick
        )
        try await supabase.from("fantasy_leagues").insert(row, returning: .minimal).execute()
    }

    func fetchFantasyLeagues(forUser uid: String) async throws -> [FantasyLeagueRow] {
        let response: [FantasyLeagueRow] = try await supabase.from("fantasy_leagues")
            .select()
            .contains("member_uids", value: [uid])
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchFantasyLeague(id: UUID) async throws -> FantasyLeagueRow? {
        let response: FantasyLeagueRow? = try? await supabase.from("fantasy_leagues")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return response
    }

    func updateFantasyLeague(_ row: FantasyLeagueRow) async throws {
        try await supabase.from("fantasy_leagues")
            .update(row, returning: .minimal)
            .eq("id", value: row.id)
            .execute()
    }

    func deleteFantasyLeague(id: UUID) async throws {
        try await supabase.from("fantasy_leagues")
            .delete(returning: .minimal)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - League Invites

    func inviteToFantasyLeague(leagueID: UUID, inviterUID: String, inviteeUID: String) async throws {
        let row = LeagueInviteRow(
            id: UUID(),
            leagueId: leagueID,
            inviterUid: inviterUID,
            inviteeUid: inviteeUID,
            status: "pending",
            createdAt: Date()
        )
        try await supabase.from("fantasy_league_invites").insert(row, returning: .minimal).execute()
    }

    func fetchFantasyLeagueInvites(forUser uid: String) async throws -> [LeagueInviteRow] {
        let response: [LeagueInviteRow] = try await supabase.from("fantasy_league_invites")
            .select()
            .eq("invitee_uid", value: uid)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func acceptFantasyLeagueInvite(inviteID: UUID, leagueID: UUID, userUID: String, teamName: String) async throws {
        // Use RPC for atomic join
        try await supabase.rpc("join_fantasy_league", params: JoinLeagueParams(
            pLeagueId: leagueID,
            pUserUid: userUID,
            pTeamName: teamName
        )).execute()

        // Update invite status
        try await supabase.from("fantasy_league_invites")
            .update(["status": "accepted"], returning: .minimal)
            .eq("id", value: inviteID)
            .execute()
    }

    func declineFantasyLeagueInvite(inviteID: UUID) async throws {
        try await supabase.from("fantasy_league_invites")
            .update(["status": "declined"], returning: .minimal)
            .eq("id", value: inviteID)
            .execute()
    }

    // MARK: - Teams

    func fetchFantasyTeams(leagueID: UUID) async throws -> [FantasyTeamRow] {
        let response: [FantasyTeamRow] = try await supabase.from("fantasy_teams")
            .select()
            .eq("league_id", value: leagueID)
            .order("total_points_for", ascending: false)
            .execute()
            .value
        return response
    }

    func updateFantasyTeam(_ row: FantasyTeamRow) async throws {
        try await supabase.from("fantasy_teams")
            .update(row, returning: .minimal)
            .eq("id", value: row.id)
            .execute()
    }

    func createFantasyTeam(leagueID: UUID, ownerUID: String, teamName: String) async throws {
        let row = FantasyTeamRow(
            id: UUID(),
            leagueId: leagueID,
            ownerUid: ownerUID,
            teamName: teamName,
            wins: 0,
            losses: 0,
            ties: 0,
            totalPointsFor: 0,
            totalPointsAgainst: 0,
            createdAt: Date()
        )
        try await supabase.from("fantasy_teams").insert(row, returning: .minimal).execute()
    }

    // MARK: - Roster

    func fetchRosterSlots(teamID: UUID) async throws -> [RosterSlotRow] {
        let response: [RosterSlotRow] = try await supabase.from("fantasy_roster_slots")
            .select()
            .eq("team_id", value: teamID)
            .order("acquired_date")
            .execute()
            .value
        return response
    }

    func fetchAllRosterSlots(leagueID: UUID) async throws -> [RosterSlotRow] {
        let response: [RosterSlotRow] = try await supabase.from("fantasy_roster_slots")
            .select()
            .eq("league_id", value: leagueID)
            .execute()
            .value
        return response
    }

    func toggleRosterSlotActive(slotID: UUID, isActive: Bool) async throws {
        try await supabase.from("fantasy_roster_slots")
            .update(["is_active": isActive], returning: .minimal)
            .eq("id", value: slotID)
            .execute()
    }

    // MARK: - Draft

    func startDraft(leagueID: UUID, draftOrder: [String]) async throws {
        struct DraftStartUpdate: Encodable {
            let draftStatus: String
            let draftOrder: [String]
            let currentDraftPickIndex: Int
            enum CodingKeys: String, CodingKey {
                case draftStatus = "draft_status"
                case draftOrder = "draft_order"
                case currentDraftPickIndex = "current_draft_pick_index"
            }
        }
        let update = DraftStartUpdate(
            draftStatus: "in_progress",
            draftOrder: draftOrder,
            currentDraftPickIndex: 0
        )
        try await supabase.from("fantasy_leagues")
            .update(update, returning: .minimal)
            .eq("id", value: leagueID)
            .execute()
    }

    func makeDraftPick(leagueID: UUID, teamID: UUID, playerUID: String, subjectName: String, round: Int, pick: Int, multiplier: Int = 1) async throws {
        try await supabase.rpc("make_draft_pick", params: MakeDraftPickParams(
            pLeagueId: leagueID,
            pTeamId: teamID,
            pPlayerUid: playerUID,
            pSubjectName: subjectName,
            pRound: round,
            pPick: pick,
            pMultiplier: multiplier
        )).execute()
    }

    func fetchDraftPicks(leagueID: UUID) async throws -> [DraftPickRow] {
        let response: [DraftPickRow] = try await supabase.from("fantasy_draft_picks")
            .select()
            .eq("league_id", value: leagueID)
            .order("pick_number")
            .execute()
            .value
        return response
    }

    func completeDraft(leagueID: UUID) async throws {
        try await supabase.from("fantasy_leagues")
            .update(["draft_status": "completed"], returning: .minimal)
            .eq("id", value: leagueID)
            .execute()
    }

    // MARK: - Matchups

    func fetchMatchups(leagueID: UUID, weekNumber: Int? = nil) async throws -> [WeeklyMatchupRow] {
        var query = supabase.from("fantasy_matchups")
            .select()
            .eq("league_id", value: leagueID)

        if let week = weekNumber {
            query = query.eq("week_number", value: week)
        }

        let response: [WeeklyMatchupRow] = try await query
            .order("week_number")
            .execute()
            .value
        return response
    }

    func upsertMatchup(_ row: WeeklyMatchupRow) async throws {
        try await supabase.from("fantasy_matchups")
            .upsert(row, returning: .minimal)
            .execute()
    }

    func finalizeWeek(leagueID: UUID, weekNumber: Int) async throws {
        try await supabase.rpc("finalize_week", params: FinalizeWeekParams(
            pLeagueId: leagueID,
            pWeekNumber: weekNumber
        )).execute()
    }

    // MARK: - Trades

    func proposeTrade(_ trade: TradeProposalRow) async throws {
        try await supabase.from("fantasy_trades")
            .insert(trade, returning: .minimal)
            .execute()
    }

    func fetchTrades(leagueID: UUID, teamID: UUID? = nil) async throws -> [TradeProposalRow] {
        var query = supabase.from("fantasy_trades")
            .select()
            .eq("league_id", value: leagueID)

        if let teamID {
            query = query.or("proposer_team_id.eq.\(teamID),receiver_team_id.eq.\(teamID)")
        }

        let response: [TradeProposalRow] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func respondToTrade(tradeID: UUID, accept: Bool) async throws {
        if accept {
            try await supabase.rpc("execute_trade", params: ExecuteTradeParams(
                pTradeId: tradeID
            )).execute()
        } else {
            try await supabase.from("fantasy_trades")
                .update(["status": "declined", "resolved_at": ISO8601DateFormatter().string(from: Date())], returning: .minimal)
                .eq("id", value: tradeID)
                .execute()
        }
    }

    // MARK: - Free Agents

    func pickupFreeAgent(leagueID: UUID, teamID: UUID, dropSlotID: UUID, playerUID: String, subjectName: String) async throws {
        try await supabase.rpc("pickup_free_agent", params: PickupFreeAgentParams(
            pLeagueId: leagueID,
            pTeamId: teamID,
            pDropSlotId: dropSlotID,
            pPlayerUid: playerUID,
            pSubjectName: subjectName
        )).execute()
    }

    // MARK: - Punishments

    func proposePunishment(_ punishment: PunishmentRow) async throws {
        try await supabase.from("fantasy_punishments")
            .insert(punishment, returning: .minimal)
            .execute()
    }

    func fetchPunishments(leagueID: UUID) async throws -> [PunishmentRow] {
        let response: [PunishmentRow] = try await supabase.from("fantasy_punishments")
            .select()
            .eq("league_id", value: leagueID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func votePunishment(punishmentID: UUID, voterUID: String) async throws {
        // Fetch current votes, add voter, update
        let current: PunishmentRow = try await supabase.from("fantasy_punishments")
            .select()
            .eq("id", value: punishmentID)
            .single()
            .execute()
            .value

        var votes = current.approvalVotes
        if !votes.contains(voterUID) {
            votes.append(voterUID)
        }

        try await supabase.from("fantasy_punishments")
            .update(["approval_votes": votes], returning: .minimal)
            .eq("id", value: punishmentID)
            .execute()
    }

    func updatePunishmentVideo(punishmentID: UUID, videoURL: String) async throws {
        try await supabase.from("fantasy_punishments")
            .update(["video_url": videoURL, "status": "completed"], returning: .minimal)
            .eq("id", value: punishmentID)
            .execute()
    }

    // MARK: - Manager Ratings

    func fetchManagerRatings(leagueID: UUID) async throws -> [ManagerRatingRow] {
        let response: [ManagerRatingRow] = try await supabase.from("fantasy_manager_ratings")
            .select()
            .eq("league_id", value: leagueID)
            .order("overall_rating", ascending: false)
            .execute()
            .value
        return response
    }

    func upsertManagerRating(_ row: ManagerRatingRow) async throws {
        try await supabase.from("fantasy_manager_ratings")
            .upsert(row, returning: .minimal)
            .execute()
    }

    // MARK: - Scoring Data

    /// Fetch timelapses for scoring: all sessions by given users within a date range.
    func fetchTimelapsesForScoring(playerUIDs: [String], startDate: Date, endDate: Date) async throws -> [TimelapseRow] {
        guard !playerUIDs.isEmpty else { return [] }

        let uuids = playerUIDs.compactMap { UUID(uuidString: $0) }
        let response: [TimelapseRow] = try await supabase.from("timelapses")
            .select()
            .in("author_id", values: uuids)
            .gte("created_at", value: startDate)
            .lte("created_at", value: endDate)
            .execute()
            .value
        return response
    }

    /// Fetch all member subjects for draft pool: returns users with their subjects.
    func fetchMemberSubjects(memberUIDs: [String]) async throws -> [(uid: String, subjects: [String])] {
        var result: [(uid: String, subjects: [String])] = []
        for uid in memberUIDs {
            guard let userRow = try await fetchUserProfile(uid: uid),
                  let subjectDicts = userRow.subjects else { continue }
            let subjects = subjectDicts.compactMap { $0["name"] }
            result.append((uid: uid, subjects: subjects))
        }
        return result
    }
}
