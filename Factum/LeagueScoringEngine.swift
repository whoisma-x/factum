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
        let playerUIDUpper = playerUID.uppercased()
        let relevant = timelapses.filter { t in
            t.authorID.uppercased() == playerUIDUpper && t.createdAt >= weekStart && t.createdAt <= weekEnd
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

    /// Elo-style K-factor for weekly rating adjustments.
    static let kFactor: Double = 32

    /// Adjust a manager's rating after a head-to-head matchup result.
    /// Uses a simplified Elo formula: base 500, K=32.
    /// `myScore` and `oppScore` are the weekly fantasy point totals.
    /// Returns the new rating for the manager.
    static func adjustedRating(
        currentRating: Double,
        opponentRating: Double,
        myScore: Double,
        oppScore: Double
    ) -> Double {
        let expectedWin = 1.0 / (1.0 + pow(10.0, (opponentRating - currentRating) / 400.0))
        let actualResult: Double
        if myScore > oppScore {
            actualResult = 1.0
        } else if myScore < oppScore {
            actualResult = 0.0
        } else {
            actualResult = 0.5
        }
        return currentRating + kFactor * (actualResult - expectedWin)
    }
}
