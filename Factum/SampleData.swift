//
//  SampleData.swift
//  Factum
//
//  Shared user identity for the local user + demo data seeding
//

import Foundation
import SwiftData

struct SampleData {
    /// A stable user ID that persists across app launches.
    static let currentUserID: UUID = {
        let key = "factum_currentUserID"
        if let stored = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let newID = UUID()
        UserDefaults.standard.set(newID.uuidString, forKey: key)
        return newID
    }()

    // MARK: - Demo Data Seeding

    /// Demo account email that receives sample data.
    private static let demoEmail = "yonafij517@suahi.com"

    /// Seeds ~2.5 years of realistic study sessions for the demo account.
    /// Deletes any old demo sessions and recreates from scratch.
    /// Guarantees sessions for the most recent 14 days (for streak).
    static func seedDemoDataIfNeeded(authorID: String, authorName: String, email: String, context: ModelContext) {
        guard email.lowercased() == demoEmail else { return }

        let key = "factum_demo_seeded_v4_\(authorID)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let calendar = Calendar.current
        let subjectDefs = StudySubject.defaultSubjects // [(name, colorHex)]

        // --- Replace subjects with standard defaults ---
        let existingDescriptor = FetchDescriptor<StudySubject>()
        let existingSubjects = (try? context.fetch(existingDescriptor)) ?? []
        for old in existingSubjects { context.delete(old) }

        var newSubjects: [StudySubject] = []
        for (index, (name, hex)) in subjectDefs.enumerated() {
            let subject = StudySubject(name: name, colorHex: hex, isUserCreated: false, sortOrder: index)
            context.insert(subject)
            newSubjects.append(subject)
        }

        let subjectsToSync = newSubjects
        let syncUID = authorID
        Task {
            try? await SupabaseService.shared.saveSubjects(subjectsToSync, forUser: syncUID)
        }

        // --- Delete old demo sessions ---
        let timelapseDescriptor = FetchDescriptor<StudyTimelapse>()
        let allTimelapses = (try? context.fetch(timelapseDescriptor)) ?? []
        for t in allTimelapses where t.authorID == authorID {
            context.delete(t)
        }

        // --- Generate realistic data ---
        var rng = SplitMix64(seed: 7919)

        let today = calendar.startOfDay(for: Date())

        // Streak: last 14 days guaranteed
        var guaranteedDays = Set<Date>()
        for offset in 0..<14 {
            if let d = calendar.date(byAdding: .day, value: -offset, to: today) {
                guaranteedDays.insert(calendar.startOfDay(for: d))
            }
        }

        // Span: Jan 2024 → today (~2.5 years)
        guard let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 5)) else { return }

        // Subject weights — Math and Science studied most, niche subjects least
        // Indices: 0=Math, 1=English, 2=Science, 3=History, 4=CS, 5=Literature,
        //          6=Physics, 7=Chemistry, 8=Economics, 9=Psychology, 10=Biology,
        //          11=Spanish, 12=Art, 13=Geography
        let subjectWeights = [18, 12, 14, 8, 12, 4, 6, 5, 5, 4, 4, 3, 3, 2]
        let totalWeight = subjectWeights.reduce(0, +)

        func pickSubject(rng: inout SplitMix64) -> Int {
            var r = Int.random(in: 0..<totalWeight, using: &rng)
            for (i, w) in subjectWeights.enumerated() {
                r -= w
                if r < 0 { return i }
            }
            return 0
        }

        var day = startDate
        while day <= today {
            let isGuaranteed = guaranteedDays.contains(calendar.startOfDay(for: day))
            let weekday = calendar.component(.weekday, from: day) // 1=Sun, 7=Sat
            let month = calendar.component(.month, from: day)
            let isWeekend = weekday == 1 || weekday == 7

            // Exam months (Dec, May) → study more; Summer (Jun-Aug) → study less
            let isExamPeriod = month == 12 || month == 5 || month == 4 || month == 11
            let isSummer = month == 6 || month == 7 || month == 8

            // Session count logic
            let roll = Int.random(in: 0...99, using: &rng)
            var sessionCount: Int
            if isGuaranteed {
                sessionCount = roll < 50 ? 1 : (roll < 80 ? 2 : 3)
            } else if isExamPeriod {
                // Exam period: rarely skip, often 2-3 sessions
                sessionCount = roll < 5 ? 0 : (roll < 35 ? 1 : (roll < 70 ? 2 : 3))
            } else if isSummer {
                // Summer: lots of rest days
                sessionCount = roll < 45 ? 0 : (roll < 80 ? 1 : 2)
            } else if isWeekend {
                // Regular weekends: often skip or single session
                sessionCount = roll < 30 ? 0 : (roll < 70 ? 1 : 2)
            } else {
                // Regular weekdays
                sessionCount = roll < 15 ? 0 : (roll < 50 ? 1 : (roll < 80 ? 2 : 3))
            }

            for s in 0..<sessionCount {
                // Duration distribution: mostly 20-90 min, occasionally up to 8 hr
                let durRoll = Int.random(in: 0...999, using: &rng)
                let durationSeconds: Int
                if durRoll < 100 {
                    durationSeconds = Int.random(in: 1200...1800, using: &rng)  // 20-30 min (quick review)
                } else if durRoll < 450 {
                    durationSeconds = Int.random(in: 1800...3600, using: &rng)  // 30-60 min (typical)
                } else if durRoll < 750 {
                    durationSeconds = Int.random(in: 3600...5400, using: &rng)  // 60-90 min (focused)
                } else if durRoll < 920 {
                    durationSeconds = Int.random(in: 5400...7200, using: &rng)  // 90-120 min (long)
                } else if durRoll < 990 {
                    durationSeconds = Int.random(in: 7200...14400, using: &rng) // 2-4 hr (marathon)
                } else {
                    durationSeconds = Int.random(in: 21600...28800, using: &rng) // 6-8 hr (extreme cram)
                }

                // Most sessions are single-subject, some multi
                let multiRoll = Int.random(in: 0...99, using: &rng)
                let subjectCount = multiRoll < 65 ? 1 : (multiRoll < 90 ? 2 : 3)

                var sessionSubjects: [(String, Int)] = []
                var remainingSeconds = durationSeconds
                var usedIndices = Set<Int>()

                for i in 0..<subjectCount {
                    var idx: Int
                    repeat {
                        idx = pickSubject(rng: &rng)
                    } while usedIndices.contains(idx) && usedIndices.count < subjectDefs.count
                    usedIndices.insert(idx)

                    let segmentSeconds: Int
                    if i == subjectCount - 1 {
                        segmentSeconds = remainingSeconds
                    } else {
                        // Give roughly even splits with some variation
                        let share = remainingSeconds / (subjectCount - i)
                        let variance = max(share / 4, 60)
                        segmentSeconds = Int.random(in: max(share - variance, 60)...share + variance, using: &rng)
                    }
                    let clamped = min(max(segmentSeconds, 60), remainingSeconds)
                    sessionSubjects.append((subjectDefs[idx].0, clamped))
                    remainingSeconds -= clamped
                    if remainingSeconds < 60 { break }
                }
                // Give any leftover to the last subject
                if remainingSeconds > 0, !sessionSubjects.isEmpty {
                    let last = sessionSubjects.count - 1
                    sessionSubjects[last].1 += remainingSeconds
                }

                // App leaves: most sessions 0-2, some 3-5, rarely extreme
                // Longer sessions tend to have more leaves
                let baseLeaves: Int
                let leaveRoll = Int.random(in: 0...999, using: &rng)
                if leaveRoll < 350 {
                    baseLeaves = 0  // 35% focused sessions
                } else if leaveRoll < 600 {
                    baseLeaves = Int.random(in: 1...3, using: &rng)
                } else if leaveRoll < 850 {
                    baseLeaves = Int.random(in: 3...8, using: &rng)
                } else if leaveRoll < 980 {
                    baseLeaves = Int.random(in: 8...20, using: &rng)  // distracted
                } else {
                    baseLeaves = Int.random(in: 30...55, using: &rng)  // extreme distraction
                }
                // Scale by duration (longer = more likely to leave)
                let durationBonus = durationSeconds > 7200 ? Int.random(in: 0...5, using: &rng) :
                                    durationSeconds > 5400 ? Int.random(in: 0...2, using: &rng) : 0
                let appLeaves = baseLeaves + durationBonus

                // Session time: morning/afternoon/evening distribution
                let timeRoll = Int.random(in: 0...99, using: &rng)
                let hour: Int
                if isWeekend {
                    // Weekends: later starts
                    hour = timeRoll < 20 ? Int.random(in: 10...12, using: &rng) :
                           timeRoll < 60 ? Int.random(in: 13...17, using: &rng) :
                                           Int.random(in: 18...22, using: &rng)
                } else {
                    // Weekdays: after-school pattern
                    hour = timeRoll < 10 ? Int.random(in: 7...8, using: &rng) :    // early bird
                           timeRoll < 30 ? Int.random(in: 15...16, using: &rng) :   // after school
                           timeRoll < 70 ? Int.random(in: 17...19, using: &rng) :   // evening
                                           Int.random(in: 20...22, using: &rng)     // night
                }
                let minute = Int.random(in: 0...59, using: &rng)
                guard let sessionDate = calendar.date(bySettingHour: hour, minute: minute, second: s * 5, of: day) else { continue }

                let primarySubject = sessionSubjects.first?.0 ?? "Math"
                let segments = sessionSubjects.map { SubjectSegment(subject: $0.0, seconds: $0.1) }

                let timelapse = StudyTimelapse(
                    authorID: authorID,
                    authorName: authorName,
                    caption: "",
                    studyDescription: "",
                    subject: primarySubject,
                    durationSeconds: durationSeconds
                )
                timelapse.createdAt = sessionDate
                timelapse.appLeaveCount = appLeaves
                timelapse.subjectSegments = segments

                context.insert(timelapse)
            }

            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        try? context.save()
        print("[FACTUM] Demo data v4 seeded for \(authorID)")
    }
}

// MARK: - Deterministic RNG

/// Simple deterministic PRNG for reproducible sample data.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
