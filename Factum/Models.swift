//
//  Models.swift
//  Pigeon
//
//  Data models for Pigeon
//

import Foundation
import SwiftData

/// Cached documents directory to avoid repeated FileManager lookups.
private let pigeonDocumentsDirectory: URL = {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}()

// MARK: - Pending Delete Store

/// Tracks timelapse IDs that were deleted locally but may not yet be deleted from
/// the cloud. syncTimelapses checks this to avoid re-inserting deleted posts.
enum PendingDeleteStore {
    private static let key = "pigeon_pending_deletes"
    
    /// In-memory cache to avoid repeated UserDefaults reads.
    private static var cached: Set<String>?
    
    static func ids() -> Set<String> {
        if let cached { return cached }
        let loaded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        cached = loaded
        return loaded
    }
    
    static func add(_ id: UUID) {
        var current = ids()
        current.insert(id.uuidString)
        cached = current
        UserDefaults.standard.set(Array(current), forKey: key)
    }
    
    static func remove(_ id: UUID) {
        var current = ids()
        current.remove(id.uuidString)
        cached = current
        UserDefaults.standard.set(Array(current), forKey: key)
    }
    
    static func contains(_ id: UUID) -> Bool {
        ids().contains(id.uuidString)
    }
}

// MARK: - Subject Segment

/// A time segment during which the user studied a specific subject.
struct SubjectSegment: Codable, Identifiable, Sendable {
    var id = UUID()
    let subject: String
    let seconds: Int
    /// Colour recorded with the session. Website sessions carry this so a
    /// subject the phone doesn't have still keeps its colour instead of gray.
    var colorHex: String? = nil
}

// MARK: - Study Quota

/// Frequency options for a study quota.
enum QuotaFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
    case scheduled   // specific days of the week
    case oneTime     // by a deadline date
}

/// Days of the week for scheduled quotas.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "Th"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "Su"
        }
    }

    /// Maps to Calendar.component(.weekday) where Sunday=1, Monday=2, etc.
    var calendarWeekday: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }
}

/// A personal study target for a specific subject.
struct StudyQuota: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var subjectName: String
    var targetMinutes: Int
    var frequency: QuotaFrequency = .daily
    var scheduledDays: [Weekday]?
    var deadline: Date?
    var createdAt: Date = Date()

    /// Backward compat alias.
    var minutesPerDay: Int { targetMinutes }

    enum CodingKeys: String, CodingKey {
        case id, subjectName, targetMinutes, frequency, scheduledDays, deadline, createdAt
        case minutesPerDay // legacy
    }

    init(id: UUID = UUID(), subjectName: String, targetMinutes: Int, frequency: QuotaFrequency = .daily, scheduledDays: [Weekday]? = nil, deadline: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.subjectName = subjectName
        self.targetMinutes = targetMinutes
        self.frequency = frequency
        self.scheduledDays = scheduledDays
        self.deadline = deadline
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subjectName = try c.decode(String.self, forKey: .subjectName)
        if let t = try? c.decode(Int.self, forKey: .targetMinutes) {
            targetMinutes = t
        } else {
            targetMinutes = try c.decode(Int.self, forKey: .minutesPerDay)
        }
        frequency = try c.decodeIfPresent(QuotaFrequency.self, forKey: .frequency) ?? .daily
        scheduledDays = try c.decodeIfPresent([Weekday].self, forKey: .scheduledDays)
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(subjectName, forKey: .subjectName)
        try c.encode(targetMinutes, forKey: .targetMinutes)
        try c.encode(frequency, forKey: .frequency)
        try c.encodeIfPresent(scheduledDays, forKey: .scheduledDays)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - User Profile

@Model
final class UserProfile {
    var id: UUID
    var firebaseUID: String?       // Auth UID — primary cloud identifier
    var displayName: String
    var username: String?          // Unique @handle (lowercase, no @ stored)
    var avatarURL: String?
    var bio: String
    var joinDate: Date
    var totalStudyMinutes: Int
    var streakDays: Int
    
    // Friend relationships stored as Auth UIDs
    var friendUIDs: [String]
    var pendingFriendRequestUIDs: [String]
    var groupIDs: [UUID]
    var isPrivate: Bool = true
    var dailyQuotasJSON: String?   // JSON-encoded [StudyQuota] (Supabase column: daily_quotas)

    /// Decoded study quotas. Backward-compatible with old DailyQuota JSON.
    var studyQuotas: [StudyQuota] {
        get {
            guard let json = dailyQuotasJSON,
                  let data = json.data(using: .utf8),
                  let quotas = try? JSONDecoder().decode([StudyQuota].self, from: data) else {
                return []
            }
            return quotas
        }
        set {
            if newValue.isEmpty {
                dailyQuotasJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue) {
                dailyQuotasJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    init(
        displayName: String,
        firebaseUID: String? = nil,
        username: String? = nil,
        avatarURL: String? = nil,
        bio: String = "",
        isPrivate: Bool = true
    ) {
        self.id = UUID()
        self.firebaseUID = firebaseUID
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.joinDate = Date()
        self.totalStudyMinutes = 0
        self.streakDays = 0
        self.friendUIDs = []
        self.pendingFriendRequestUIDs = []
        self.groupIDs = []
        self.isPrivate = isPrivate
    }
}

// MARK: - Study Timelapse

@Model
final class StudyTimelapse {
    var id: UUID
    var authorID: String           // Auth UID of the author
    var authorName: String
    var authorAvatarURL: String?
    var caption: String
    var studyDescription: String
    var subject: String
    var durationSeconds: Int
    var createdAt: Date
    var videoFileName: String?
    var thumbnailData: Data?
    var afterPhotoData: Data?       // Second photo for before/after posts
    var videoDownloadURL: String?   // Storage download URL
    var thumbnailDownloadURL: String?
    var isLandscape: Bool
    var likeCount: Int
    var likedByUIDs: [String]
    var commentCount: Int
    var googlePhotosBackedUp: Bool
    var appLeaveCount: Int = 0
    var offTaskSeconds: Int = 0
    var subjectSegmentsJSON: String? // JSON-encoded [SubjectSegment]
    var cloudSynced: Bool = false    // true once successfully uploaded to Supabase
    var syncRetryCount: Int = 0      // number of failed sync attempts (for backoff)
    var lastSyncAttempt: Date?       // when the last sync attempt was made
    var pigeonOrigin: String?        // Carrier Pigeon flight origin landmark
    var pigeonDestination: String?   // Carrier Pigeon flight destination landmark
    var descriptionRarity: String?   // PunRarity raw value (e.g. "legendary")
    
    /// Cache for decoded subject segments, invalidated when JSON changes.
    @Transient private var _cachedSegments: [SubjectSegment]?
    @Transient private var _cachedJSON: String?

    /// Decoded subject segments. Returns a single segment from `subject` + `durationSeconds` if no JSON is stored (backwards compatibility).
    var subjectSegments: [SubjectSegment] {
        get {
            // Return cached value if JSON hasn't changed
            if let cached = _cachedSegments, _cachedJSON == subjectSegmentsJSON {
                return cached
            }
            let result: [SubjectSegment]
            if let json = subjectSegmentsJSON,
               let data = json.data(using: .utf8),
               let segments = try? JSONDecoder().decode([SubjectSegment].self, from: data),
               !segments.isEmpty {
                result = segments
            } else {
                // Fallback: single segment from the legacy subject field
                result = [SubjectSegment(subject: subject, seconds: durationSeconds)]
            }
            _cachedSegments = result
            _cachedJSON = subjectSegmentsJSON
            return result
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                subjectSegmentsJSON = String(data: data, encoding: .utf8)
            }
            _cachedSegments = newValue
            _cachedJSON = subjectSegmentsJSON
        }
    }
    
    /// Whether this post has more than one subject studied.
    var hasMultipleSubjects: Bool {
        subjectSegments.count > 1
    }
    
    /// Returns the local video URL if the file exists on disk,
    /// otherwise falls back to the cloud download URL from Supabase Storage.
    var videoURL: URL? {
        // Try local file first
        if let videoFileName {
            let url = pigeonDocumentsDirectory.appendingPathComponent(videoFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fall back to cloud URL
        if let videoDownloadURL, let url = URL(string: videoDownloadURL) {
            return url
        }
        return nil
    }
    
    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let secs = durationSeconds % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
    
    init(
        authorID: String,
        authorName: String,
        authorAvatarURL: String? = nil,
        caption: String,
        studyDescription: String,
        subject: String,
        durationSeconds: Int,
        videoFileName: String? = nil,
        thumbnailData: Data? = nil,
        isLandscape: Bool = false
    ) {
        self.id = UUID()
        self.authorID = authorID
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.caption = caption
        self.studyDescription = studyDescription
        self.subject = subject
        self.durationSeconds = durationSeconds
        self.createdAt = Date()
        self.videoFileName = videoFileName
        self.thumbnailData = thumbnailData
        self.isLandscape = isLandscape
        self.likeCount = 0
        self.likedByUIDs = []
        self.commentCount = 0
        self.googlePhotosBackedUp = false
        self.appLeaveCount = 0
    }
}

// MARK: - Study Group

@Model
final class StudyGroup {
    var id: UUID
    var name: String
    var groupDescription: String
    var creatorID: String           // Auth UID of the creator
    var memberIDs: [String]         // Auth UIDs of all members
    var createdAt: Date
    var iconName: String
    
    init(name: String, groupDescription: String, creatorID: String, iconName: String = "book.fill") {
        self.id = UUID()
        self.name = name
        self.groupDescription = groupDescription
        self.creatorID = creatorID
        self.memberIDs = [creatorID]
        self.createdAt = Date()
        self.iconName = iconName
    }
}
