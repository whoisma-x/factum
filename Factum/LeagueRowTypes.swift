//
//  LeagueRowTypes.swift
//  Pigeon
//
//  Codable row types for Supabase fantasy league tables
//

import Foundation

// MARK: - Fantasy League Row

struct FantasyLeagueRow: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var commissionerUid: String
    var memberUids: [String]
    var seasonStartDate: Date
    var seasonEndDate: Date
    var createdAt: Date
    var maxRosterSize: Int
    var benchSize: Int
    var draftStatus: String
    var draftOrder: [String]
    var currentDraftPickIndex: Int
    var playoffTeamCount: Int
    var weeklyMatchupsJson: String?
    var scoringConfigJson: String?
    var slotConfigJson: String?
    var iconName: String
    var description: String
    var draftSecondsPerPick: Int

    /// Decode the slot multiplier config. Default: 3×3x, 2×2x, 1×1x for a 6-slot roster.
    var slotMultipliers: [Int] {
        if let json = slotConfigJson,
           let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([Int].self, from: data) {
            return arr
        }
        return Self.defaultSlotConfig(rosterSize: maxRosterSize)
    }

    /// Default slot config: half the slots at 3x, a third at 2x, rest at 1x.
    static func defaultSlotConfig(rosterSize: Int) -> [Int] {
        guard rosterSize > 0 else { return [] }
        let count3x = max(1, rosterSize / 2)          // ~half at 3x
        let count2x = max(1, (rosterSize - count3x) / 2 + (rosterSize - count3x) % 2) // ~quarter at 2x
        let count1x = rosterSize - count3x - count2x  // rest at 1x
        return Array(repeating: 3, count: count3x)
             + Array(repeating: 2, count: count2x)
             + Array(repeating: 1, count: max(0, count1x))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case commissionerUid = "commissioner_uid"
        case memberUids = "member_uids"
        case seasonStartDate = "season_start_date"
        case seasonEndDate = "season_end_date"
        case createdAt = "created_at"
        case maxRosterSize = "max_roster_size"
        case benchSize = "bench_size"
        case draftStatus = "draft_status"
        case draftOrder = "draft_order"
        case currentDraftPickIndex = "current_draft_pick_index"
        case playoffTeamCount = "playoff_team_count"
        case weeklyMatchupsJson = "weekly_matchups_json"
        case scoringConfigJson = "scoring_config_json"
        case slotConfigJson = "slot_config_json"
        case iconName = "icon_name"
        case draftSecondsPerPick = "draft_seconds_per_pick"
    }
}

// MARK: - Fantasy Team Row

struct FantasyTeamRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var ownerUid: String
    var teamName: String
    var wins: Int
    var losses: Int
    var ties: Int
    var totalPointsFor: Double
    var totalPointsAgainst: Double
    var playoffSeed: Int?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, wins, losses, ties
        case leagueId = "league_id"
        case ownerUid = "owner_uid"
        case teamName = "team_name"
        case totalPointsFor = "total_points_for"
        case totalPointsAgainst = "total_points_against"
        case playoffSeed = "playoff_seed"
        case createdAt = "created_at"
    }
}

// MARK: - Roster Slot Row

struct RosterSlotRow: Codable, Sendable, Identifiable {
    var id: UUID
    var teamId: UUID
    var leagueId: UUID
    var playerUid: String
    var subjectName: String
    var isActive: Bool
    var acquiredDate: Date
    var acquiredVia: String
    var multiplier: Int

    enum CodingKeys: String, CodingKey {
        case id, multiplier
        case teamId = "team_id"
        case leagueId = "league_id"
        case playerUid = "player_uid"
        case subjectName = "subject_name"
        case isActive = "is_active"
        case acquiredDate = "acquired_date"
        case acquiredVia = "acquired_via"
    }
}

// MARK: - Weekly Matchup Row

struct WeeklyMatchupRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var weekNumber: Int
    var team1Id: UUID
    var team2Id: UUID
    var team1Score: Double
    var team2Score: Double
    var winnerTeamId: UUID?
    var weekStartDate: Date
    var weekEndDate: Date
    var isPlayoff: Bool
    var isBye: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case weekNumber = "week_number"
        case team1Id = "team1_id"
        case team2Id = "team2_id"
        case team1Score = "team1_score"
        case team2Score = "team2_score"
        case winnerTeamId = "winner_team_id"
        case weekStartDate = "week_start_date"
        case weekEndDate = "week_end_date"
        case isPlayoff = "is_playoff"
        case isBye = "is_bye"
    }
}

// MARK: - Trade Proposal Row

struct TradeProposalRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var proposerTeamId: UUID
    var receiverTeamId: UUID
    var offeredSlotIds: [String]
    var requestedSlotIds: [String]
    var status: String
    var createdAt: Date
    var resolvedAt: Date?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case id, status, message
        case leagueId = "league_id"
        case proposerTeamId = "proposer_team_id"
        case receiverTeamId = "receiver_team_id"
        case offeredSlotIds = "offered_slot_ids"
        case requestedSlotIds = "requested_slot_ids"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

// MARK: - Draft Pick Row

struct DraftPickRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var teamId: UUID
    var roundNumber: Int
    var pickNumber: Int
    var playerUid: String
    var subjectName: String
    var pickedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case teamId = "team_id"
        case roundNumber = "round_number"
        case pickNumber = "pick_number"
        case playerUid = "player_uid"
        case subjectName = "subject_name"
        case pickedAt = "picked_at"
    }
}

// MARK: - Punishment Row

struct PunishmentRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var weekNumber: Int
    var targetUid: String
    var reason: String
    var punishmentDescription: String
    var videoUrl: String?
    var approvalVotes: [String]
    var status: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reason, status
        case leagueId = "league_id"
        case weekNumber = "week_number"
        case targetUid = "target_uid"
        case punishmentDescription = "punishment_description"
        case videoUrl = "video_url"
        case approvalVotes = "approval_votes"
        case createdAt = "created_at"
    }
}

// MARK: - League Invite Row

struct LeagueInviteRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var inviterUid: String
    var inviteeUid: String
    var status: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case leagueId = "league_id"
        case inviterUid = "inviter_uid"
        case inviteeUid = "invitee_uid"
        case createdAt = "created_at"
    }
}

// MARK: - Manager Rating Row

struct ManagerRatingRow: Codable, Sendable, Identifiable {
    var id: UUID
    var leagueId: UUID
    var managerUid: String
    var overallRating: Double
    var draftGrade: Double
    var tradeGrade: Double
    var rosterManagementGrade: Double
    var consistencyGrade: Double
    var weeklyRatingsJson: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case managerUid = "manager_uid"
        case overallRating = "overall_rating"
        case draftGrade = "draft_grade"
        case tradeGrade = "trade_grade"
        case rosterManagementGrade = "roster_management_grade"
        case consistencyGrade = "consistency_grade"
        case weeklyRatingsJson = "weekly_ratings_json"
        case updatedAt = "updated_at"
    }
}

// MARK: - RPC Parameter Types

struct JoinLeagueParams: Codable, Sendable {
    let pLeagueId: UUID
    let pUserUid: String
    let pTeamName: String

    enum CodingKeys: String, CodingKey {
        case pLeagueId = "p_league_id"
        case pUserUid = "p_user_uid"
        case pTeamName = "p_team_name"
    }
}

struct MakeDraftPickParams: Codable, Sendable {
    let pLeagueId: UUID
    let pTeamId: UUID
    let pPlayerUid: String
    let pSubjectName: String
    let pRound: Int
    let pPick: Int
    let pMultiplier: Int

    enum CodingKeys: String, CodingKey {
        case pLeagueId = "p_league_id"
        case pTeamId = "p_team_id"
        case pPlayerUid = "p_player_uid"
        case pSubjectName = "p_subject_name"
        case pRound = "p_round"
        case pPick = "p_pick"
        case pMultiplier = "p_multiplier"
    }
}

struct ExecuteTradeParams: Codable, Sendable {
    let pTradeId: UUID

    enum CodingKeys: String, CodingKey {
        case pTradeId = "p_trade_id"
    }
}

struct PickupFreeAgentParams: Codable, Sendable {
    let pLeagueId: UUID
    let pTeamId: UUID
    let pDropSlotId: UUID
    let pPlayerUid: String
    let pSubjectName: String

    enum CodingKeys: String, CodingKey {
        case pLeagueId = "p_league_id"
        case pTeamId = "p_team_id"
        case pDropSlotId = "p_drop_slot_id"
        case pPlayerUid = "p_player_uid"
        case pSubjectName = "p_subject_name"
    }
}

struct FinalizeWeekParams: Codable, Sendable {
    let pLeagueId: UUID
    let pWeekNumber: Int

    enum CodingKeys: String, CodingKey {
        case pLeagueId = "p_league_id"
        case pWeekNumber = "p_week_number"
    }
}
