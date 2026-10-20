//
//  LeagueScoringEngine.swift
//  Pigeon
//
//  Scoring engine and manager rating system for fantasy study leagues
//

import Foundation

// MARK: - Scoring Configuration

/// Commissioner-configurable scoring weights for a league.
struct ScoringConfig: Codable, Sendable {
    var studyPointsPerMinute: Double = 1.0
    var appLeavePenalty: Double = 2.0
    var offTaskPenaltyPerMinute: Double = 0.5
    var focusBonusPoints: Double = 5.0          // Bonus for 0 app leaves in session >30min
    var marathonBonusPoints: Double = 10.0       // Bonus for single session >2hrs
    var marathonThresholdSeconds: Int = 7200     // 2 hours
    var focusBonusMinSessionSeconds: Int = 1800  // 30 minutes

    static let `default` = ScoringConfig()

    /// Decode from league's scoringConfigJSON, falling back to defaults.
    static func from(json: String?) -> ScoringConfig {
        guard let json, let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(ScoringConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Player Score Result

/// The computed score for a single roster slot (player-subject combo) over a time window.
struct PlayerScoreResult: Sendable {
    let playerUID: String
    let subjectName: String
    let totalStudyMinutes: Double
    let totalAppLeaves: Int
    let totalOffTaskMinutes: Double
    let sessionCount: Int
    let focusBonuses: Int               // Number of focused sessions
    let marathonBonuses: Int            // Number of marathon sessions
    let rawScore: Double
    let finalScore: Double              // max(0, rawScore) — before multiplier
    let multiplier: Int                 // Slot multiplier (1x, 2x, 3x)
    let multipliedScore: Double         // finalScore × multiplier
}

// MARK: - Score Calculator

enum LeagueScoringEngine {

    /// Calculate the fantasy score for a player-subject combo over a time window.
    /// Uses locally-synced StudyTimelapse data.
    static func calculateScore(
        playerUID: String,
        subject: String,
        timelapses: [StudyTimelapse],
        weekStart: Date,
        weekEnd: Date,
        config: ScoringConfig = .default,
        multiplier: Int = 1
    ) -> PlayerScoreResult {
        // Filter timelapses for this player in the time window
        let relevant = timelapses.filter { t in
            t.authorID == playerUID && t.createdAt >= weekStart && t.createdAt <= weekEnd
        }

        var totalStudySeconds: Double = 0
        var totalAppLeaves = 0
        var totalOffTaskSeconds: Double = 0
        var sessionCount = 0
        var focusBonuses = 0
        var marathonBonuses = 0

        for timelapse in relevant {
            // Check if this timelapse has the subject in its segments
            let segments = timelapse.subjectSegments
            let matchingSegments = segments.filter { $0.subject == subject }

            guard !matchingSegments.isEmpty else { continue }
            sessionCount += 1

            // Sum study time for this subject only
            let subjectSeconds = matchingSegments.reduce(0) { $0 + $1.seconds }
            totalStudySeconds += Double(subjectSeconds)

            // Proportional share of penalties for multi-subject sessions
            let totalSessionSeconds = max(1, segments.reduce(0) { $0 + $1.seconds })
            let proportion = Double(subjectSeconds) / Double(totalSessionSeconds)

            totalAppLeaves += Int(Double(timelapse.appLeaveCount) * proportion)
            totalOffTaskSeconds += Double(timelapse.offTaskSeconds) * proportion

            // Focus bonus: 0 app leaves for a session >30min
            if timelapse.appLeaveCount == 0 && timelapse.durationSeconds >= config.focusBonusMinSessionSeconds {
                focusBonuses += 1
            }

            // Marathon bonus: single session >2hrs
            if timelapse.durationSeconds >= config.marathonThresholdSeconds {
                marathonBonuses += 1
            }
        }

        let studyMinutes = totalStudySeconds / 60.0
        let offTaskMinutes = totalOffTaskSeconds / 60.0

        let rawScore = (studyMinutes * config.studyPointsPerMinute)
            - (Double(totalAppLeaves) * config.appLeavePenalty)
            - (offTaskMinutes * config.offTaskPenaltyPerMinute)
            + (Double(focusBonuses) * config.focusBonusPoints)
            + (Double(marathonBonuses) * config.marathonBonusPoints)

        let baseScore = max(0, rawScore)
        return PlayerScoreResult(
            playerUID: playerUID,
            subjectName: subject,
            totalStudyMinutes: studyMinutes,
            totalAppLeaves: totalAppLeaves,
            totalOffTaskMinutes: offTaskMinutes,
            sessionCount: sessionCount,
            focusBonuses: focusBonuses,
            marathonBonuses: marathonBonuses,
            rawScore: rawScore,
            finalScore: baseScore,
            multiplier: multiplier,
            multipliedScore: baseScore * Double(multiplier)
        )
    }

    /// Calculate total team score for a week by summing all active roster slot scores (with multipliers applied).
    static func calculateTeamScore(
        rosterSlots: [RosterSlot],
        timelapses: [StudyTimelapse],
        weekStart: Date,
        weekEnd: Date,
        config: ScoringConfig = .default
    ) -> (total: Double, slotScores: [UUID: PlayerScoreResult]) {
        var total: Double = 0
        var slotScores: [UUID: PlayerScoreResult] = [:]

        for slot in rosterSlots where slot.isActive {
            let result = calculateScore(
                playerUID: slot.playerUID,
                subject: slot.subjectName,
                timelapses: timelapses,
                weekStart: weekStart,
                weekEnd: weekEnd,
                config: config,
                multiplier: slot.multiplier
            )
            slotScores[slot.id] = result
            total += result.multipliedScore
        }

        return (total, slotScores)
    }

    // MARK: - Week Calculation Helpers

    /// Returns the Monday 00:00 and Sunday 23:59:59 for the week containing the given date.
    static func weekBounds(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)?
            .addingTimeInterval(-1) ?? date
        return (startOfWeek, endOfWeek)
    }

    /// Returns the week number within a league season.
    static func weekNumber(for date: Date, seasonStart: Date) -> Int {
        let calendar = Calendar(identifier: .iso8601)
        let days = calendar.dateComponents([.day], from: seasonStart, to: date).day ?? 0
        return max(1, (days / 7) + 1)
    }
}

// MARK: - Manager Rating Calculator

enum ManagerRatingEngine {

    /// Calculate draft grade based on how drafted players have performed.
    /// Compares each draft pick's total points to the league average for that position.
    static func draftGrade(
        myPicks: [DraftPick],
        allRosterSlots: [RosterSlot],
        timelapses: [StudyTimelapse],
        seasonStart: Date,
        now: Date,
        config: ScoringConfig
    ) -> Double {
        guard !myPicks.isEmpty else { return 50 }

        var myTotal: Double = 0
        var leagueTotal: Double = 0
        var leagueCount = 0

        for slot in allRosterSlots {
            let result = LeagueScoringEngine.calculateScore(
                playerUID: slot.playerUID,
                subject: slot.subjectName,
                timelapses: timelapses,
                weekStart: seasonStart,
                weekEnd: now,
                config: config
            )
            leagueTotal += result.finalScore
            leagueCount += 1

            if myPicks.contains(where: { $0.playerUID == slot.playerUID && $0.subjectName == slot.subjectName }) {
                myTotal += result.finalScore
            }
        }

        let leagueAvg = leagueCount > 0 ? leagueTotal / Double(leagueCount) : 0
        let myAvg = !myPicks.isEmpty ? myTotal / Double(myPicks.count) : 0

        guard leagueAvg > 0 else { return 50 }
        // Score relative to league average: 50 = average, scales ±50
        return min(100, max(0, 50 + ((myAvg - leagueAvg) / leagueAvg) * 50))
    }

    /// Trade grade based on net point gain/loss from completed trades.
    static func tradeGrade(
        trades: [TradeProposal],
        myTeamID: UUID,
        rosterSlots: [RosterSlot],
        timelapses: [StudyTimelapse],
        seasonStart: Date,
        now: Date,
        config: ScoringConfig
    ) -> Double {
        let completedTrades = trades.filter { $0.status == "accepted" }
        guard !completedTrades.isEmpty else { return 50 }

        // Simplified: look at current roster performance of traded-for players
        // vs traded-away players. Full implementation would track historical swaps.
        return 50 // Baseline — improves as trade history accumulates
    }

    /// Roster management grade based on lineup optimization and free agent activity.
    static func rosterManagementGrade(
        rosterSlots: [RosterSlot],
        timelapses: [StudyTimelapse],
        weekStart: Date,
        weekEnd: Date,
        config: ScoringConfig
    ) -> Double {
        let activeSlots = rosterSlots.filter { $0.isActive }
        let benchSlots = rosterSlots.filter { !$0.isActive }

        guard !activeSlots.isEmpty else { return 50 }

        // Check if the owner has their best players starting
        var activeScores: [Double] = []
        var benchScores: [Double] = []

        for slot in activeSlots {
            let result = LeagueScoringEngine.calculateScore(
                playerUID: slot.playerUID,
                subject: slot.subjectName,
                timelapses: timelapses,
                weekStart: weekStart,
                weekEnd: weekEnd,
                config: config
            )
            activeScores.append(result.finalScore)
        }

        for slot in benchSlots {
            let result = LeagueScoringEngine.calculateScore(
                playerUID: slot.playerUID,
                subject: slot.subjectName,
                timelapses: timelapses,
                weekStart: weekStart,
                weekEnd: weekEnd,
                config: config
            )
            benchScores.append(result.finalScore)
        }

        // If any bench player outscored an active player, deduct points
        let worstActive = activeScores.min() ?? 0
        let bestBench = benchScores.max() ?? 0

        if bestBench > worstActive && worstActive > 0 {
            // Penalty for leaving points on the bench
            let missDelta = (bestBench - worstActive) / max(1, bestBench)
            return max(0, 80 - missDelta * 100)
        }

        // Free agent activity bonus
        let freeAgentPickups = rosterSlots.filter { $0.acquiredVia == "free_agent" }.count
        let activityBonus = min(20.0, Double(freeAgentPickups) * 5.0)

        return min(100, 70 + activityBonus)
    }

    /// Consistency grade based on week-over-week performance stability.
    static func consistencyGrade(weeklyScores: [Double]) -> Double {
        guard weeklyScores.count >= 2 else { return 50 }

        let mean = weeklyScores.reduce(0, +) / Double(weeklyScores.count)
        guard mean > 0 else { return 50 }

        let variance = weeklyScores.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeklyScores.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / mean // Coefficient of variation

        // Lower CV = more consistent = higher grade
        // CV of 0 = perfect consistency = 100
        // CV of 1+ = highly inconsistent = low grade
        return min(100, max(0, 100 - cv * 80))
    }
}
