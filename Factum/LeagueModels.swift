//
//  LeagueModels.swift
//  Pigeon
//
//  Fantasy Study League data models
//

import Foundation
import SwiftData

// MARK: - League Format Presets

enum LeagueFormat: String, CaseIterable, Identifiable {
    case ib = "IB"
    case ap = "AP"
    case aLevel = "A-Level"
    case standard = "Standard"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .ib: return "6 HL/SL subjects, no bench"
        case .ap: return "5 AP classes + 2 bench"
        case .aLevel: return "3 subjects, no bench"
        case .standard: return "8 active + 3 bench"
        case .custom: return "Configure everything"
        }
    }

    var icon: String {
        switch self {
        case .ib: return "globe.americas.fill"
        case .ap: return "star.circle.fill"
        case .aLevel: return "building.columns.fill"
        case .standard: return "trophy.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var rosterSize: Int {
        switch self {
        case .ib: return 6
        case .ap: return 5
        case .aLevel: return 3
        case .standard: return 8
        case .custom: return 8
        }
    }

    var benchSize: Int {
        switch self {
        case .ib: return 0
        case .ap: return 2
        case .aLevel: return 0
        case .standard: return 3
        case .custom: return 3
        }
    }

    /// Default slot multipliers for this format
    var slotMultipliers: [Int] {
        switch self {
        case .ib:
            // IB: 3 HL subjects at 3×, 3 SL subjects at 2×
            return [3, 3, 3, 2, 2, 2]
        case .ap:
            // AP: Top 2 at 3×, next 2 at 2×, last 1 at 1×
            return [3, 3, 2, 2, 1]
        case .aLevel:
            // A-Level: All 3 subjects weighted equally at 3×
            return [3, 3, 3]
        case .standard:
            return FantasyLeagueRow.defaultSlotConfig(rosterSize: 8)
        case .custom:
            return FantasyLeagueRow.defaultSlotConfig(rosterSize: 8)
        }
    }

    /// Description of the slot layout for the format picker
    var slotDescription: String {
        switch self {
        case .ib: return "3× HL slots, 2× SL slots"
        case .ap: return "3× top slots, 2× mid, 1× flex"
        case .aLevel: return "All slots 3× (equal weight)"
        case .standard: return "Mixed 3×/2×/1× multipliers"
        case .custom: return "You choose everything"
        }
    }
}

// MARK: - Fantasy League

@Model
final class FantasyLeague {
    var id: UUID
    var name: String
    var commissionerUID: String              // Auth UID of the league creator
    var memberUIDs: [String]                 // All league member Auth UIDs
    var seasonStartDate: Date
    var seasonEndDate: Date
    var createdAt: Date
    var maxRosterSize: Int                   // Active roster slots (default 8)
    var benchSize: Int                       // Bench slots (default 3)
    var draftStatus: String                  // "pending" | "in_progress" | "completed"
    var draftOrder: [String]                 // Auth UIDs in snake-draft pick order
    var currentDraftPickIndex: Int           // Which pick we're on (0-based)
    var playoffTeamCount: Int                // Teams qualifying for playoffs (default 4)
    var weeklyMatchupsJSON: String?          // JSON-encoded matchup schedule
    var scoringConfigJSON: String?           // JSON-encoded ScoringConfig overrides
    var slotConfigJSON: String?              // JSON-encoded [Int] of multipliers for active slots (e.g. [3,3,3,2,2,1])
    var iconName: String                     // SF Symbol for display
    var leagueDescription: String
    var draftSecondsPerPick: Int             // Timer per draft pick (default 90)

    init(
        name: String,
        commissionerUID: String,
        seasonStartDate: Date = Date(),
        seasonEndDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date(),
        maxRosterSize: Int = 8,
        benchSize: Int = 3,
        playoffTeamCount: Int = 4,
        iconName: String = "trophy.fill",
        leagueDescription: String = "",
        draftSecondsPerPick: Int = 90
    ) {
        self.id = UUID()
        self.name = name
        self.commissionerUID = commissionerUID
        self.memberUIDs = [commissionerUID]
        self.seasonStartDate = seasonStartDate
        self.seasonEndDate = seasonEndDate
        self.createdAt = Date()
        self.maxRosterSize = maxRosterSize
        self.benchSize = benchSize
        self.draftStatus = "pending"
        self.draftOrder = []
        self.currentDraftPickIndex = 0
        self.playoffTeamCount = playoffTeamCount
        self.iconName = iconName
        self.leagueDescription = leagueDescription
        self.draftSecondsPerPick = draftSecondsPerPick
    }
}

// MARK: - Fantasy Team

@Model
final class FantasyTeam {
    var id: UUID
    var leagueID: UUID
    var ownerUID: String                     // Auth UID of the team owner
    var teamName: String
    var wins: Int
    var losses: Int
    var ties: Int
    var totalPointsFor: Double
    var totalPointsAgainst: Double
    var playoffSeed: Int?
    var createdAt: Date

    init(leagueID: UUID, ownerUID: String, teamName: String) {
        self.id = UUID()
        self.leagueID = leagueID
        self.ownerUID = ownerUID
        self.teamName = teamName
        self.wins = 0
        self.losses = 0
        self.ties = 0
        self.totalPointsFor = 0
        self.totalPointsAgainst = 0
        self.createdAt = Date()
    }
}

// MARK: - Roster Slot

@Model
final class RosterSlot {
    var id: UUID
    var teamID: UUID
    var leagueID: UUID
    var playerUID: String                    // Auth UID of the student being "drafted"
    var subjectName: String                  // The subject (e.g., "HL Math AA")
    var isActive: Bool                       // true = in lineup, false = benched
    var acquiredDate: Date
    var acquiredVia: String                  // "draft" | "trade" | "free_agent"
    var multiplier: Int                      // Point multiplier for this slot (1x, 2x, 3x)

    init(
        teamID: UUID,
        leagueID: UUID,
        playerUID: String,
        subjectName: String,
        isActive: Bool = true,
        acquiredVia: String = "draft",
        multiplier: Int = 1
    ) {
        self.id = UUID()
        self.teamID = teamID
        self.leagueID = leagueID
        self.playerUID = playerUID
        self.subjectName = subjectName
        self.isActive = isActive
        self.acquiredDate = Date()
        self.acquiredVia = acquiredVia
        self.multiplier = multiplier
    }
}

// MARK: - Weekly Matchup

@Model
final class WeeklyMatchup {
    var id: UUID
    var leagueID: UUID
    var weekNumber: Int
    var team1ID: UUID
    var team2ID: UUID
    var team1Score: Double
    var team2Score: Double
    var winnerTeamID: UUID?
    var weekStartDate: Date
    var weekEndDate: Date
    var isPlayoff: Bool
    var isBye: Bool                          // true if one team has a bye

    init(
        leagueID: UUID,
        weekNumber: Int,
        team1ID: UUID,
        team2ID: UUID,
        weekStartDate: Date,
        weekEndDate: Date,
        isPlayoff: Bool = false,
        isBye: Bool = false
    ) {
        self.id = UUID()
        self.leagueID = leagueID
        self.weekNumber = weekNumber
        self.team1ID = team1ID
        self.team2ID = team2ID
        self.team1Score = 0
        self.team2Score = 0
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.isPlayoff = isPlayoff
        self.isBye = isBye
    }
}

// MARK: - Trade Proposal

@Model
final class TradeProposal {
    var id: UUID
    var leagueID: UUID
    var proposerTeamID: UUID
    var receiverTeamID: UUID
    var offeredSlotIDs: [String]             // UUID strings of RosterSlot
    var requestedSlotIDs: [String]           // UUID strings of RosterSlot
    var status: String                       // "pending" | "accepted" | "declined" | "cancelled"
    var createdAt: Date
    var resolvedAt: Date?
    var message: String?

    init(
        leagueID: UUID,
        proposerTeamID: UUID,
        receiverTeamID: UUID,
        offeredSlotIDs: [String],
        requestedSlotIDs: [String],
        message: String? = nil
    ) {
        self.id = UUID()
        self.leagueID = leagueID
        self.proposerTeamID = proposerTeamID
        self.receiverTeamID = receiverTeamID
        self.offeredSlotIDs = offeredSlotIDs
        self.requestedSlotIDs = requestedSlotIDs
        self.status = "pending"
        self.createdAt = Date()
        self.message = message
    }
}

// MARK: - Draft Pick

@Model
final class DraftPick {
    var id: UUID
    var leagueID: UUID
    var teamID: UUID
    var roundNumber: Int
    var pickNumber: Int                      // Overall pick number (1-based)
    var playerUID: String
    var subjectName: String
    var pickedAt: Date

    init(
        leagueID: UUID,
        teamID: UUID,
        roundNumber: Int,
        pickNumber: Int,
        playerUID: String,
        subjectName: String
    ) {
        self.id = UUID()
        self.leagueID = leagueID
        self.teamID = teamID
        self.roundNumber = roundNumber
        self.pickNumber = pickNumber
        self.playerUID = playerUID
        self.subjectName = subjectName
        self.pickedAt = Date()
    }
}

// MARK: - Punishment

@Model
final class Punishment {
    var id: UUID
    var leagueID: UUID
    var weekNumber: Int
    var targetUID: String                    // Auth UID of the punished user
    var reason: String                       // "lowest_score" | "least_studied"
    var punishmentDescription: String
    var videoURL: String?
    var thumbnailData: Data?
    var approvalVotes: [String]              // Auth UIDs who approved
    var status: String                       // "proposed" | "approved" | "completed"
    var createdAt: Date

    init(
        leagueID: UUID,
        weekNumber: Int,
        targetUID: String,
        reason: String,
        punishmentDescription: String = ""
    ) {
        self.id = UUID()
        self.leagueID = leagueID
        self.weekNumber = weekNumber
        self.targetUID = targetUID
        self.reason = reason
        self.punishmentDescription = punishmentDescription
        self.approvalVotes = []
        self.status = "proposed"
        self.createdAt = Date()
    }
}

// MARK: - League Invite

@Model
final class LeagueInvite {
    var id: UUID
    var leagueID: UUID
    var inviterUID: String
    var inviteeUID: String
    var status: String                       // "pending" | "accepted" | "declined"
    var createdAt: Date

    init(leagueID: UUID, inviterUID: String, inviteeUID: String) {
        self.id = UUID()
        self.leagueID = leagueID
        self.inviterUID = inviterUID
        self.inviteeUID = inviteeUID
        self.status = "pending"
        self.createdAt = Date()
    }
}

// MARK: - Manager Rating

@Model
final class ManagerRating {
    var id: UUID
    var leagueID: UUID
    var managerUID: String                   // Auth UID
    var overallRating: Double                // 0-100 composite
    var draftGrade: Double                   // 0-100
    var tradeGrade: Double                   // 0-100
    var rosterManagementGrade: Double        // 0-100
    var consistencyGrade: Double             // 0-100
    var weeklyRatingsJSON: String?           // JSON-encoded historical weekly ratings
    var updatedAt: Date

    init(leagueID: UUID, managerUID: String) {
        self.id = UUID()
        self.leagueID = leagueID
        self.managerUID = managerUID
        self.overallRating = 50
        self.draftGrade = 50
        self.tradeGrade = 50
        self.rosterManagementGrade = 50
        self.consistencyGrade = 50
        self.updatedAt = Date()
    }

    /// Letter grade from numeric score (A+ through F)
    var letterGrade: String {
        switch overallRating {
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

    /// Recalculate overall rating from component grades
    func recalculate() {
        overallRating = (draftGrade * 0.20)
            + (tradeGrade * 0.20)
            + (rosterManagementGrade * 0.30)
            + (consistencyGrade * 0.30)
        updatedAt = Date()
    }
}
