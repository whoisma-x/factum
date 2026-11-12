//
//  BotStudyGenerator.swift
//  Pigeon
//
//  Generates realistic study timelapse data for the 7 bot league members
//  and upserts it directly to Supabase. Uses deterministic UUIDs and
//  date-seeded PRNGs so re-running is idempotent.
//

import Foundation
import CryptoKit

// MARK: - Deterministic UUID (v5)

private enum DeterministicUUID {
    /// Fixed namespace UUID for bot study sessions.
    private static let namespace = UUID(uuidString: "B07DA7A0-5700-4000-A000-FA7A5700B075")!

    /// Generate a deterministic UUID v5 from a string key.
    /// Same key always produces the same UUID.
    static func v5(from key: String) -> UUID {
        let nsBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let keyBytes = Array(key.utf8)
        let input = nsBytes + keyBytes
        let hash = Insecure.SHA1.hash(data: input)
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant 1
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - Deterministic PRNG

private struct BotSplitMix64: RandomNumberGenerator {
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

// MARK: - Bot Personality

private struct BotPersonality {
    let uid: String
    let displayName: String
    let subjects: [(name: String, weight: Int)]

    // Study volume
    let dailySessionRange: ClosedRange<Int>     // sessions per study day
    let skipDayProbability: Double               // 0.0=never skips, 1.0=always skips
    let weekendSkipBoost: Double                 // extra skip probability on weekends

    // Duration ranges (seconds)
    let shortRange: ClosedRange<Int>
    let normalRange: ClosedRange<Int>
    let longRange: ClosedRange<Int>
    let longProbability: Double                  // chance of long session (0-1)

    // Focus
    let appLeaveRange: ClosedRange<Int>
    let zeroLeaveProbability: Double             // chance of zero app leaves
    let offTaskMultiplier: Double                // offTaskSeconds ≈ appLeaves × this × 60

    // Captions and descriptions
    let captions: [String]
    let descriptions: [String]
}

// MARK: - Bot Registry

private enum BotRegistry {
    static let bots: [BotPersonality] = [
        // Sophie Chen — Grinder: studies constantly, very focused
        BotPersonality(
            uid: "A1B2C3D4-4444-4000-A000-000000000004",
            displayName: "Sophie Chen",
            subjects: [
                ("English A HL", 25), ("History HL", 22), ("Psychology HL", 20),
                ("Math AI SL", 13), ("Biology SL", 10), ("French B SL", 10)
            ],
            dailySessionRange: 1...3,
            skipDayProbability: 0.05,
            weekendSkipBoost: 0.10,
            shortRange: 2400...3600,
            normalRange: 3600...7200,
            longRange: 7200...14400,
            longProbability: 0.25,
            appLeaveRange: 0...3,
            zeroLeaveProbability: 0.70,
            offTaskMultiplier: 0.8,
            captions: [
                "essay grind", "history notes", "psych review", "locked in",
                "math practice", "bio chapter", "french vocab", "study sesh",
                "IA writing", "paper prep", "reading time", "late night grind"
            ],
            descriptions: [
                "Working on extended essay draft", "Cold War historiography notes",
                "Abnormal psychology case studies", "Paper 1 timed practice",
                "Statistics and probability review", "Ecology unit summary",
                "French oral prep", "History IA bibliography",
                "Psychology experiment design", "English comparative essay"
            ]
        ),

        // Aisha Patel — Steady: consistent daily sessions, focused
        BotPersonality(
            uid: "A1B2C3D4-6666-4000-A000-000000000006",
            displayName: "Aisha Patel",
            subjects: [
                ("Physics HL", 24), ("Math AA HL", 24), ("Computer Science HL", 20),
                ("Chemistry SL", 12), ("English A SL", 10), ("French Ab SL", 10)
            ],
            dailySessionRange: 1...2,
            skipDayProbability: 0.10,
            weekendSkipBoost: 0.15,
            shortRange: 2400...3600,
            normalRange: 3600...5400,
            longRange: 5400...10800,
            longProbability: 0.20,
            appLeaveRange: 0...4,
            zeroLeaveProbability: 0.50,
            offTaskMultiplier: 1.0,
            captions: [
                "physics grind", "math problems", "CS project", "chem review",
                "coding session", "practice problems", "IA work", "lab prep",
                "english essay", "french drill", "study time", "debugging"
            ],
            descriptions: [
                "Electromagnetic induction problems", "Integration techniques practice",
                "Java data structures implementation", "Stoichiometry review",
                "Physics IA data analysis", "Algorithms and sorting",
                "Calculus optimization problems", "Circuit analysis practice",
                "CS IA development", "Mechanics problem set"
            ]
        ),

        // Priya Sharma — Science-heavy: long labs, concentrated subjects
        BotPersonality(
            uid: "A1B2C3D4-2222-4000-A000-000000000002",
            displayName: "Priya Sharma",
            subjects: [
                ("Biology HL", 26), ("Chemistry HL", 24), ("Math AA HL", 22),
                ("English A SL", 10), ("French B SL", 9), ("Psychology SL", 9)
            ],
            dailySessionRange: 1...2,
            skipDayProbability: 0.15,
            weekendSkipBoost: 0.15,
            shortRange: 1800...3000,
            normalRange: 3000...5400,
            longRange: 5400...10800,
            longProbability: 0.20,
            appLeaveRange: 0...5,
            zeroLeaveProbability: 0.40,
            offTaskMultiplier: 1.0,
            captions: [
                "bio grind", "chem lab report", "math review", "science marathon",
                "bio IA", "organic chem", "practice paper", "lab data",
                "psych notes", "french practice", "english IO", "study sesh"
            ],
            descriptions: [
                "Cell division and mitosis", "Organic chemistry mechanisms",
                "Complex numbers practice", "Lab report analysis",
                "Biology IA data collection", "Titration calculations",
                "Genetics and heredity", "Calculus problem set",
                "Energetics and thermochemistry", "Ecology fieldwork writeup"
            ]
        ),

        // Ethan Reyes — Humanities buff: consistent, medium sessions
        BotPersonality(
            uid: "A1B2C3D4-7777-4000-A000-000000000007",
            displayName: "Ethan Reyes",
            subjects: [
                ("English A HL", 25), ("History HL", 24), ("Philosophy HL", 21),
                ("Spanish B SL", 12), ("Math AI SL", 10), ("Biology SL", 8)
            ],
            dailySessionRange: 1...2,
            skipDayProbability: 0.20,
            weekendSkipBoost: 0.15,
            shortRange: 1800...2700,
            normalRange: 2700...4500,
            longRange: 4500...7200,
            longProbability: 0.12,
            appLeaveRange: 0...4,
            zeroLeaveProbability: 0.45,
            offTaskMultiplier: 1.0,
            captions: [
                "english essay", "history reading", "philosophy paper", "locked in",
                "spanish vocab", "math hw", "bio notes", "IA draft",
                "close reading", "TOK prep", "writing time", "exam prep"
            ],
            descriptions: [
                "Poetry analysis close reading", "Cold War causes essay",
                "Epistemology essay draft", "Spanish oral commentary prep",
                "Statistics practice problems", "Cell biology review",
                "History IA source analysis", "Philosophy of mind notes",
                "Comparative literature essay", "TOK exhibition planning"
            ]
        ),

        // Jordan Kim — Average: normal IB student pattern
        BotPersonality(
            uid: "A1B2C3D4-1111-4000-A000-000000000001",
            displayName: "Jordan Kim",
            subjects: [
                ("Math AA HL", 25), ("Physics HL", 23), ("English A HL", 20),
                ("Economics SL", 12), ("Spanish B SL", 10), ("Chemistry SL", 10)
            ],
            dailySessionRange: 1...2,
            skipDayProbability: 0.25,
            weekendSkipBoost: 0.20,
            shortRange: 1800...2700,
            normalRange: 2700...4500,
            longRange: 4500...7200,
            longProbability: 0.10,
            appLeaveRange: 0...6,
            zeroLeaveProbability: 0.35,
            offTaskMultiplier: 1.2,
            captions: [
                "math grind", "physics problems", "english IO prep", "econ notes",
                "spanish vocab", "chem review", "practice paper", "IA work",
                "late night math", "study sesh", "exam prep", "hw time"
            ],
            descriptions: [
                "Integration by parts practice", "Mechanics problems set",
                "Oral commentary prep", "Microeconomics chapter review",
                "Vocabulary drill", "Stoichiometry practice",
                "Math IA exploration draft", "Electricity and magnetism",
                "Sequences and series", "Paper 1 practice essay"
            ]
        ),

        // Marcus Johnson — Night owl: fewer but longer sessions
        BotPersonality(
            uid: "A1B2C3D4-3333-4000-A000-000000000003",
            displayName: "Marcus Johnson",
            subjects: [
                ("Math AA HL", 26), ("Computer Science HL", 24), ("Physics HL", 22),
                ("English A SL", 10), ("Economics SL", 10), ("Spanish Ab SL", 8)
            ],
            dailySessionRange: 1...2,
            skipDayProbability: 0.30,
            weekendSkipBoost: 0.15,
            shortRange: 2400...3600,
            normalRange: 3600...5400,
            longRange: 5400...10800,
            longProbability: 0.22,
            appLeaveRange: 0...8,
            zeroLeaveProbability: 0.30,
            offTaskMultiplier: 1.3,
            captions: [
                "late night code", "math grind", "physics hw", "CS project",
                "debugging", "algorithm practice", "IA coding", "study sesh",
                "english essay", "econ cramming", "practice test", "coding"
            ],
            descriptions: [
                "Java recursion practice", "Calculus derivatives",
                "Waves and optics problems", "CS IA backend development",
                "Binary search implementation", "Linear algebra review",
                "Physics lab analysis", "Database query practice",
                "Sorting algorithms", "Math exploration research"
            ]
        ),

        // Tyler Brooks — Slacker: minimal effort, short sessions
        BotPersonality(
            uid: "A1B2C3D4-5555-4000-A000-000000000005",
            displayName: "Tyler Brooks",
            subjects: [
                ("Business HL", 22), ("Economics HL", 22), ("English A SL", 16),
                ("Math AI SL", 16), ("Spanish B SL", 12), ("Geography SL", 12)
            ],
            dailySessionRange: 1...1,
            skipDayProbability: 0.45,
            weekendSkipBoost: 0.25,
            shortRange: 1200...2100,
            normalRange: 2100...3600,
            longRange: 3600...5400,
            longProbability: 0.05,
            appLeaveRange: 2...12,
            zeroLeaveProbability: 0.10,
            offTaskMultiplier: 1.8,
            captions: [
                "barely studying", "last minute hw", "cramming", "trying",
                "why is this due tmrw", "pain", "business IA", "econ test tmrw",
                "need to pass", "going through it", "pls help", "survival mode"
            ],
            descriptions: [
                "Flipping through notes", "Skimming the textbook",
                "Watching review videos", "Half-hearted practice questions",
                "Supply and demand diagrams", "Business IA draft attempt",
                "Geography case study reading", "Spanish vocab cramming",
                "Math practice (kind of)", "Last minute essay outline"
            ]
        ),
    ]

    static let botUIDs: Set<String> = Set(bots.map(\.uid))
}

// MARK: - Bot Study Generator

enum BotStudyGenerator {

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }()

    private static let lastGenKey = "botStudyGen_lastDate"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    /// One-time reset: the previous run set lastGenKey even though 0/106 uploads succeeded
    /// (RLS policy blocked them). Clear the key so the bot data regenerates.
    private static let rlsRetryKey = "botStudyGen_rlsRetry_v1"
    static func resetIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: rlsRetryKey) else { return }
        UserDefaults.standard.removeObject(forKey: lastGenKey)
        UserDefaults.standard.set(true, forKey: rlsRetryKey)
        print("[BOT] Reset lastGenKey to retry after RLS fix")
    }

    /// Generate and upload bot study sessions to Supabase.
    /// Called during syncLeagueData before fetching league member timelapses.
    static func generateAndUpload(leagues: [FantasyLeagueRow]) async {
        resetIfNeeded()
        // Find leagues that contain bot UIDs
        let botLeagues = leagues.filter { league in
            league.memberUids.contains(where: { BotRegistry.botUIDs.contains($0) })
        }
        guard !botLeagues.isEmpty else { return }

        // Use the earliest season start across all bot leagues
        let seasonStart = botLeagues.map(\.seasonStartDate).min() ?? Date()
        let today = calendar.startOfDay(for: Date())

        // Determine generation range
        let lastGenDate = UserDefaults.standard.object(forKey: lastGenKey) as? Date
        let startDate: Date
        if let last = lastGenDate {
            // Start from day after last generated date
            startDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? today
        } else {
            startDate = calendar.startOfDay(for: seasonStart)
        }

        guard startDate <= today else {
            return  // Already up to date
        }

        // Count days to generate
        let dayCount = (calendar.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1
        print("[BOT] Generating study data for \(dayCount) day(s) across \(BotRegistry.bots.count) bots")

        var allRows: [TimelapseRow] = []

        for bot in BotRegistry.bots {
            var day = startDate
            while day <= today {
                let dateString = dateFormatter.string(from: day)
                let seedValue = hashSeed(bot.uid + "_" + dateString)
                var rng = BotSplitMix64(seed: seedValue)

                let sessions = generateDaySessions(bot: bot, date: day, rng: &rng)
                allRows.append(contentsOf: sessions)

                day = calendar.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(86400)
            }
        }

        guard !allRows.isEmpty else {
            UserDefaults.standard.set(today, forKey: lastGenKey)
            return
        }

        print("[BOT] Uploading \(allRows.count) bot sessions to Supabase")

        // Batch upload
        var successCount = 0
        let batchSize = 20
        for batchStart in stride(from: 0, to: allRows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allRows.count)
            let batch = Array(allRows[batchStart..<batchEnd])

            for row in batch {
                do {
                    try await SupabaseService.shared.saveTimelapseRow(row)
                    successCount += 1
                } catch {
                    // Log but don't block — some rows may already exist or have transient failures
                    print("[BOT] Upload failed for \(row.id.uuidString.prefix(8)): \(error.localizedDescription)")
                }
            }

            // Small delay between batches
            if batchEnd < allRows.count {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        print("[BOT] Uploaded \(successCount)/\(allRows.count) bot sessions")
        // Only advance the date marker if at least one upload succeeded;
        // otherwise the failed batch would be silently skipped on next launch.
        if successCount > 0 {
            UserDefaults.standard.set(today, forKey: lastGenKey)
        }
    }

    // MARK: - Day Session Generation

    private static func generateDaySessions(
        bot: BotPersonality,
        date: Date,
        rng: inout BotSplitMix64
    ) -> [TimelapseRow] {
        let weekday = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat
        let isWeekend = weekday == 1 || weekday == 7

        // Decide whether to skip this day
        let skipProb = bot.skipDayProbability + (isWeekend ? bot.weekendSkipBoost : 0)
        let skipRoll = Double.random(in: 0...1, using: &rng)
        if skipRoll < skipProb {
            return []
        }

        // Pick session count
        let sessionCount = Int.random(in: bot.dailySessionRange, using: &rng)
        var rows: [TimelapseRow] = []

        for sessionIndex in 0..<sessionCount {
            let row = buildSession(bot: bot, date: date, sessionIndex: sessionIndex, rng: &rng)
            rows.append(row)
        }

        return rows
    }

    // MARK: - Single Session Builder

    private static func buildSession(
        bot: BotPersonality,
        date: Date,
        sessionIndex: Int,
        rng: inout BotSplitMix64
    ) -> TimelapseRow {
        let dateString = dateFormatter.string(from: date)
        let sessionID = DeterministicUUID.v5(from: "\(bot.uid)_\(dateString)_\(sessionIndex)")

        // Duration
        let durRoll = Double.random(in: 0...1, using: &rng)
        let durationSeconds: Int
        if durRoll < bot.longProbability {
            durationSeconds = Int.random(in: bot.longRange, using: &rng)
        } else if durRoll < bot.longProbability + 0.45 {
            durationSeconds = Int.random(in: bot.normalRange, using: &rng)
        } else {
            durationSeconds = Int.random(in: bot.shortRange, using: &rng)
        }

        // Subject selection (potentially multi-subject)
        let multiRoll = Int.random(in: 0...99, using: &rng)
        let subjectCount = multiRoll < 65 ? 1 : (multiRoll < 90 ? 2 : 3)

        var segments: [(subject: String, seconds: Int)] = []
        var remainingSeconds = durationSeconds
        var usedSubjects = Set<String>()

        for i in 0..<subjectCount {
            let subject = pickSubject(bot: bot, excluding: usedSubjects, rng: &rng)
            usedSubjects.insert(subject)

            let segmentSeconds: Int
            if i == subjectCount - 1 {
                segmentSeconds = remainingSeconds
            } else {
                let share = remainingSeconds / (subjectCount - i)
                let variance = max(share / 4, 60)
                let lower = max(share - variance, 120)
                let upper = share + variance
                segmentSeconds = min(Int.random(in: lower...upper, using: &rng), remainingSeconds - 120)
            }

            let clamped = min(max(segmentSeconds, 120), remainingSeconds)
            segments.append((subject: subject, seconds: clamped))
            remainingSeconds -= clamped
            if remainingSeconds < 120 { break }
        }

        // Distribute leftover to last segment
        if remainingSeconds > 0, !segments.isEmpty {
            segments[segments.count - 1].seconds += remainingSeconds
        }

        let primarySubject = segments.first?.subject ?? bot.subjects.first!.name

        // App leaves
        let appLeaves: Int
        let focusRoll = Double.random(in: 0...1, using: &rng)
        if focusRoll < bot.zeroLeaveProbability {
            appLeaves = 0
        } else {
            appLeaves = Int.random(in: bot.appLeaveRange, using: &rng)
        }

        // Off-task seconds proportional to app leaves
        let offTaskSeconds = appLeaves > 0
            ? Int(Double(appLeaves) * bot.offTaskMultiplier * Double.random(in: 30...90, using: &rng))
            : 0

        // Session time of day
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        let hour: Int
        let timeRoll = Int.random(in: 0...99, using: &rng)
        if isWeekend {
            hour = timeRoll < 20 ? Int.random(in: 10...12, using: &rng) :
                   timeRoll < 60 ? Int.random(in: 13...17, using: &rng) :
                                   Int.random(in: 18...22, using: &rng)
        } else {
            hour = timeRoll < 10 ? Int.random(in: 7...8, using: &rng) :
                   timeRoll < 30 ? Int.random(in: 15...16, using: &rng) :
                   timeRoll < 70 ? Int.random(in: 17...19, using: &rng) :
                                   Int.random(in: 20...23, using: &rng)
        }
        let minute = Int.random(in: 0...59, using: &rng)
        let sessionDate = calendar.date(bySettingHour: hour, minute: minute, second: sessionIndex * 7, of: date)
            ?? date

        // Caption and description
        let caption = bot.captions[Int.random(in: 0..<bot.captions.count, using: &rng)]
        let description = bot.descriptions[Int.random(in: 0..<bot.descriptions.count, using: &rng)]

        // Build subject segments JSON
        let segmentsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: segments.map { ["subject": $0.subject, "seconds": $0.seconds] }),
           let str = String(data: data, encoding: .utf8) {
            segmentsJSON = str
        } else {
            segmentsJSON = "[{\"subject\":\"\(primarySubject)\",\"seconds\":\(durationSeconds)}]"
        }

        return TimelapseRow(
            id: sessionID,
            authorId: UUID(uuidString: bot.uid)!,
            authorName: bot.displayName,
            authorAvatarUrl: nil,
            caption: caption,
            studyDescription: description,
            subject: primarySubject,
            durationSeconds: durationSeconds,
            createdAt: sessionDate,
            isLandscape: false,
            likeCount: 0,
            likedByUids: [],
            commentCount: 0,
            videoDownloadUrl: nil,
            thumbnailDownloadUrl: nil,
            appLeaveCount: appLeaves,
            offTaskSeconds: offTaskSeconds,
            subjectSegmentsJson: segmentsJSON,
            pigeonOrigin: nil,
            pigeonDestination: nil,
            descriptionRarity: nil
        )
    }

    // MARK: - Helpers

    private static func pickSubject(
        bot: BotPersonality,
        excluding: Set<String>,
        rng: inout BotSplitMix64
    ) -> String {
        let available = bot.subjects.filter { !excluding.contains($0.name) }
        guard !available.isEmpty else {
            return bot.subjects.first!.name
        }
        let totalWeight = available.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<totalWeight, using: &rng)
        for (name, weight) in available {
            roll -= weight
            if roll < 0 { return name }
        }
        return available.first!.name
    }

    /// Convert a string to a stable UInt64 seed for the PRNG.
    private static func hashSeed(_ key: String) -> UInt64 {
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.withUnsafeBytes { bytes in
            bytes.load(as: UInt64.self)
        }
    }
}
