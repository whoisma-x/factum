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
    
    static func ids() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    
    static func add(_ id: UUID) {
        var current = ids()
        current.insert(id.uuidString)
        UserDefaults.standard.set(Array(current), forKey: key)
    }
    
    static func remove(_ id: UUID) {
        var current = ids()
        current.remove(id.uuidString)
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
}

// MARK: - User Profile

@Model
final class UserProfile {
    var id: UUID
    var firebaseUID: String?       // Auth UID — primary cloud identifier
    var displayName: String
    var username: String?          // Unique @handle (lowercase, no @ stored)
    var email: String
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

    init(
        displayName: String,
        email: String,
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
        self.email = email
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
