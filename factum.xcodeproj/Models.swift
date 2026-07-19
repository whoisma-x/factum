//
//  Models.swift
//  Factum
//
//  Data models for Factum
//

import Foundation
import SwiftData

// MARK: - User Profile

@Model
final class UserProfile {
    var id: UUID
    var firebaseUID: String?       // Firebase Auth UID — primary cloud identifier
    var displayName: String
    var email: String
    var avatarURL: String?
    var bio: String
    var joinDate: Date
    var totalStudyMinutes: Int
    var streakDays: Int
    
    // Friend relationships stored as Firebase UIDs
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
    
    /// Convert to Firestore document dictionary
    func toFirestoreDict() -> [String: Any] {
        var dict: [String: Any] = [
            "displayName": displayName,
            "email": email,
            "bio": bio,
            "joinDate": joinDate.timeIntervalSince1970,
            "totalStudyMinutes": totalStudyMinutes,
            "streakDays": streakDays,
            "friendUIDs": friendUIDs,
            "pendingFriendRequestUIDs": pendingFriendRequestUIDs,
        ]
        if let avatarURL { dict["avatarURL"] = avatarURL }
        return dict
    }
}

// MARK: - Study Timelapse

@Model
final class StudyTimelapse {
    var id: UUID
    var authorID: String           // Firebase UID of the author
    var authorName: String
    var authorAvatarURL: String?
    var caption: String
    var studyDescription: String
    var subject: String
    var durationSeconds: Int
    var createdAt: Date
    var videoFileName: String?
    var thumbnailData: Data?
    var videoDownloadURL: String?   // Firebase Storage download URL
    var thumbnailDownloadURL: String?
    var likeCount: Int
    var likedByUIDs: [String]
    var commentCount: Int
    
    var videoURL: URL? {
        guard let videoFileName else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(videoFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
        thumbnailData: Data? = nil
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
        self.likeCount = 0
        self.likedByUIDs = []
        self.commentCount = 0
    }
    
    /// Convert to Firestore document dictionary
    func toFirestoreDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "authorID": authorID,
            "authorName": authorName,
            "caption": caption,
            "studyDescription": studyDescription,
            "subject": subject,
            "durationSeconds": durationSeconds,
            "createdAt": createdAt.timeIntervalSince1970,
            "likeCount": likeCount,
            "likedByUIDs": likedByUIDs,
            "commentCount": commentCount,
        ]
        if let authorAvatarURL { dict["authorAvatarURL"] = authorAvatarURL }
        if let videoDownloadURL { dict["videoDownloadURL"] = videoDownloadURL }
        if let thumbnailDownloadURL { dict["thumbnailDownloadURL"] = thumbnailDownloadURL }
        return dict
    }
}

// MARK: - Comment

@Model
final class TimelapseComment {
    var id: UUID
    var timelapseID: UUID
    var authorID: String           // Firebase UID
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

