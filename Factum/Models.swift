//
//  Models.swift
//  Factum
//
//  Data models for Factum
//

import Foundation
import SwiftData

/// Cached documents directory to avoid repeated FileManager lookups.
private let factumDocumentsDirectory: URL = {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}()

// MARK: - Pending Delete Store

/// Tracks timelapse IDs that were deleted locally but may not yet be deleted from
/// the cloud. syncTimelapses checks this to avoid re-inserting deleted posts.
enum PendingDeleteStore {
    private static let key = "factum_pending_deletes"
    
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
struct SubjectSegment: Codable, Identifiable {
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
    
    init(
        displayName: String,
        email: String,
        firebaseUID: String? = nil,
        avatarURL: String? = nil,
        bio: String = ""
    ) {
        self.id = UUID()
        self.firebaseUID = firebaseUID
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.bio = bio
        self.joinDate = Date()
        self.totalStudyMinutes = 0
        self.streakDays = 0
        self.friendUIDs = []
        self.pendingFriendRequestUIDs = []
        self.groupIDs = []
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
    var subjectSegmentsJSON: String? // JSON-encoded [SubjectSegment]
    
    /// Decoded subject segments. Returns a single segment from `subject` + `durationSeconds` if no JSON is stored (backwards compatibility).
    var subjectSegments: [SubjectSegment] {
        get {
            if let json = subjectSegmentsJSON,
               let data = json.data(using: .utf8),
               let segments = try? JSONDecoder().decode([SubjectSegment].self, from: data),
               !segments.isEmpty {
                return segments
            }
            // Fallback: single segment from the legacy subject field
            return [SubjectSegment(subject: subject, seconds: durationSeconds)]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                subjectSegmentsJSON = String(data: data, encoding: .utf8)
            }
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
            let url = factumDocumentsDirectory.appendingPathComponent(videoFileName)
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

// MARK: - Comment

@Model
final class TimelapseComment {
    var id: UUID
    var timelapseID: UUID
    var authorID: String           // Auth UID
    var authorName: String
    var text: String
    var createdAt: Date
    
    init(timelapseID: UUID, authorID: String, authorName: String, text: String) {
        self.id = UUID()
        self.timelapseID = timelapseID
        self.authorID = authorID
        self.authorName = authorName
        self.text = text
        self.createdAt = Date()
    }
}

// MARK: - Study Group

@Model
final class StudyGroup {
    var id: UUID
    var name: String
    var groupDescription: String
    var creatorID: UUID
    var memberIDs: [UUID]
    var createdAt: Date
    var iconName: String
    
    init(name: String, groupDescription: String, creatorID: UUID, iconName: String = "book.fill") {
        self.id = UUID()
        self.name = name
        self.groupDescription = groupDescription
        self.creatorID = creatorID
        self.memberIDs = [creatorID]
        self.createdAt = Date()
        self.iconName = iconName
    }
}
