//
//  SupabaseService.swift
//  Factum
//
//  Supabase database CRUD for users, timelapses, and comments
//

import Foundation
import Supabase
import SwiftData

// MARK: - Codable Row Types (map 1:1 to Supabase tables)

struct UserRow: Codable {
    let uid: UUID
    var displayName: String
    var email: String
    var avatarUrl: String?
    var bio: String
    var joinDate: Date
    var totalStudyMinutes: Int
    var streakDays: Int
    var friendUids: [String]
    var pendingFriendRequestUids: [String]
    var subjects: [[String: String]]?
    
    enum CodingKeys: String, CodingKey {
        case uid
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
        case bio
        case joinDate = "join_date"
        case totalStudyMinutes = "total_study_minutes"
        case streakDays = "streak_days"
        case friendUids = "friend_uids"
        case pendingFriendRequestUids = "pending_friend_request_uids"
        case subjects
    }
}

struct TimelapseRow: Codable {
    let id: UUID
    var authorId: UUID
    var authorName: String
    var authorAvatarUrl: String?
    var caption: String
    var studyDescription: String
    var subject: String
    var durationSeconds: Int
    var createdAt: Date
    var isLandscape: Bool
    var likeCount: Int
    var likedByUids: [String]
    var commentCount: Int
    var videoDownloadUrl: String?
    var thumbnailDownloadUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case caption
        case studyDescription = "study_description"
        case subject
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case isLandscape = "is_landscape"
        case likeCount = "like_count"
        case likedByUids = "liked_by_uids"
        case commentCount = "comment_count"
        case videoDownloadUrl = "video_download_url"
        case thumbnailDownloadUrl = "thumbnail_download_url"
    }
}

struct SupaCommentRow: Codable {
    let id: UUID
    var timelapseId: UUID
    var authorId: String
    var authorName: String
    var text: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case timelapseId = "timelapse_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case text
        case createdAt = "created_at"
    }
}

// MARK: - RPC Parameter Types

struct AddFriendParams: Codable {
    let currentUid: UUID
    let friendUid: String
    
    enum CodingKeys: String, CodingKey {
        case currentUid = "current_uid"
        case friendUid = "friend_uid"
    }
}

struct RemoveFriendParams: Codable {
    let currentUid: UUID
    let friendUid: String
    
    enum CodingKeys: String, CodingKey {
        case currentUid = "current_uid"
        case friendUid = "friend_uid"
    }
}

struct ToggleLikeParams: Codable {
    let pTimelapseId: UUID
    let pUserUid: String
    let pIsLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case pTimelapseId = "p_timelapse_id"
        case pUserUid = "p_user_uid"
        case pIsLiked = "p_is_liked"
    }
}

struct IncrementCommentCountParams: Codable {
    let pTimelapseId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pTimelapseId = "p_timelapse_id"
    }
}

// MARK: - Supabase Service

final class SupabaseService {
    static let shared = SupabaseService()
    
    private init() {}
    
    // MARK: - User Profiles
    
    /// Save or update a user profile in Supabase. Row key = Supabase Auth UID.
    func saveUserProfile(_ profile: UserProfile) async throws {
        guard let uidString = profile.firebaseUID,
              let uid = UUID(uuidString: uidString) else { return }
        
        let row = UserRow(
            uid: uid,
            displayName: profile.displayName,
            email: profile.email,
            avatarUrl: profile.avatarURL,
            bio: profile.bio,
            joinDate: profile.joinDate,
            totalStudyMinutes: profile.totalStudyMinutes,
            streakDays: profile.streakDays,
            friendUids: profile.friendUIDs,
            pendingFriendRequestUids: profile.pendingFriendRequestUIDs
        )
        
        try await supabase.from("users").upsert(row).execute()
    }
    
    /// Fetch a user profile by UID.
    func fetchUserProfile(uid: String) async throws -> UserRow? {
        guard let uuid = UUID(uuidString: uid) else { return nil }
        
        let response: UserRow? = try? await supabase.from("users")
            .select()
            .eq("uid", value: uuid)
            .single()
            .execute()
            .value
        
        return response
    }
    
    /// Search users by display name prefix (case-insensitive).
    func searchUsers(query: String, limit: Int = 20) async throws -> [UserRow] {
        let response: [UserRow] = try await supabase.from("users")
            .select()
            .ilike("display_name", pattern: "\(query)%")
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Timelapses
    
    /// Save a timelapse to Supabase.
    func saveTimelapse(_ timelapse: StudyTimelapse) async throws {
        guard let authorUUID = UUID(uuidString: timelapse.authorID) else { return }
        
        let row = TimelapseRow(
            id: timelapse.id,
            authorId: authorUUID,
            authorName: timelapse.authorName,
            authorAvatarUrl: timelapse.authorAvatarURL,
            caption: timelapse.caption,
            studyDescription: timelapse.studyDescription,
            subject: timelapse.subject,
            durationSeconds: timelapse.durationSeconds,
            createdAt: timelapse.createdAt,
            isLandscape: timelapse.isLandscape,
            likeCount: timelapse.likeCount,
            likedByUids: timelapse.likedByUIDs,
            commentCount: timelapse.commentCount,
            videoDownloadUrl: timelapse.videoDownloadURL,
            thumbnailDownloadUrl: timelapse.thumbnailDownloadURL
        )
        
        try await supabase.from("timelapses").upsert(row).execute()
    }
    
    /// Save a pre-built timelapse row to Supabase (avoids @Model access off main actor).
    func saveTimelapseRow(_ row: TimelapseRow) async throws {
        try await supabase.from("timelapses").upsert(row).execute()
    }
    
    /// Delete a timelapse and its comments from Supabase.
    func deleteTimelapse(_ timelapse: StudyTimelapse) async throws {
        try await deleteTimelapse(timelapse.id)
    }
    
    /// Delete a timelapse by ID from Supabase.
    func deleteTimelapse(_ id: UUID) async throws {
        // Comments are deleted automatically via ON DELETE CASCADE
        try await supabase.from("timelapses")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    /// Fetch timelapses for a specific user.
    func fetchTimelapses(forUser uid: String, limit: Int = 50) async throws -> [TimelapseRow] {
        guard let uuid = UUID(uuidString: uid) else { return [] }
        
        let response: [TimelapseRow] = try await supabase.from("timelapses")
            .select()
            .eq("author_id", value: uuid)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    /// Fetch timelapses from a list of user UIDs (for social feed).
    func fetchFeed(friendUIDs: [String], limit: Int = 50) async throws -> [TimelapseRow] {
        guard !friendUIDs.isEmpty else { return [] }
        
        // Supabase has no 30-item in-query limit like Firestore
        let uuids = friendUIDs.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }
        
        let response: [TimelapseRow] = try await supabase.from("timelapses")
            .select()
            .in("author_id", values: uuids)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Friends
    
    /// Add a friend UID to the current user's friend list.
    func addFriend(currentUID: String, friendUID: String) async throws {
        guard let uuid = UUID(uuidString: currentUID) else { return }
        try await supabase.rpc(
            "add_friend",
            params: AddFriendParams(currentUid: uuid, friendUid: friendUID)
        ).execute()
    }
    
    /// Remove a friend UID from the current user's friend list.
    func removeFriend(currentUID: String, friendUID: String) async throws {
        guard let uuid = UUID(uuidString: currentUID) else { return }
        try await supabase.rpc(
            "remove_friend",
            params: RemoveFriendParams(currentUid: uuid, friendUid: friendUID)
        ).execute()
    }
    
    // MARK: - Likes
    
    /// Toggle like on a timelapse.
    func toggleLike(timelapseID: String, userUID: String, isLiked: Bool) async throws {
        guard let uuid = UUID(uuidString: timelapseID) else { return }
        try await supabase.rpc(
            "toggle_like",
            params: ToggleLikeParams(pTimelapseId: uuid, pUserUid: userUID, pIsLiked: isLiked)
        ).execute()
    }
    
    // MARK: - Comments
    
    /// Save a comment to Supabase and increment the timelapse's commentCount.
    func saveComment(_ comment: TimelapseComment) async throws {
        let row = SupaCommentRow(
            id: comment.id,
            timelapseId: comment.timelapseID,
            authorId: comment.authorID,
            authorName: comment.authorName,
            text: comment.text,
            createdAt: comment.createdAt
        )
        
        try await supabase.from("comments").insert(row).execute()
        
        // Increment comment count on the timelapse
        try await supabase.rpc(
            "increment_comment_count",
            params: IncrementCommentCountParams(pTimelapseId: comment.timelapseID)
        ).execute()
    }
    
    /// Save a pre-built comment row to Supabase (avoids @Model access off main actor).
    func saveCommentRow(_ row: SupaCommentRow) async throws {
        try await supabase.from("comments").insert(row).execute()
        
        // Increment comment count on the timelapse
        try await supabase.rpc(
            "increment_comment_count",
            params: IncrementCommentCountParams(pTimelapseId: row.timelapseId)
        ).execute()
    }
    
    /// Fetch comments for a specific timelapse.
    func fetchComments(forTimelapse timelapseID: String, limit: Int = 100) async throws -> [SupaCommentRow] {
        guard let uuid = UUID(uuidString: timelapseID) else { return [] }
        
        let response: [SupaCommentRow] = try await supabase.from("comments")
            .select()
            .eq("timelapse_id", value: uuid)
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    /// Sync comments for a timelapse from Supabase into SwiftData.
    @MainActor
    func syncComments(forTimelapse timelapseID: UUID, context: ModelContext) async {
        do {
            let rows = try await fetchComments(forTimelapse: timelapseID.uuidString)
            
            let descriptor = FetchDescriptor<TimelapseComment>(
                predicate: #Predicate { $0.timelapseID == timelapseID }
            )
            let localComments = (try? context.fetch(descriptor)) ?? []
            let localIDSet = Set(localComments.map { $0.id.uuidString })
            
            var insertedCount = 0
            for row in rows {
                guard !localIDSet.contains(row.id.uuidString) else { continue }
                
                let comment = TimelapseComment(
                    timelapseID: row.timelapseId,
                    authorID: row.authorId,
                    authorName: row.authorName,
                    text: row.text
                )
                comment.id = row.id
                comment.createdAt = row.createdAt
                context.insert(comment)
                insertedCount += 1
            }
            if insertedCount > 0 {
                print("[SYNC] Synced \(insertedCount) comments for timelapse \(timelapseID.uuidString.prefix(8))")
            }
        } catch {
            print("[SYNC] Comment sync error for \(timelapseID.uuidString.prefix(8)): \(error)")
        }
    }
    
    // MARK: - Study Subjects
    
    /// Save user's study subjects to Supabase.
    func saveSubjects(_ subjects: [StudySubject], forUser uid: String) async throws {
        guard let uuid = UUID(uuidString: uid) else { return }
        
        let subjectDicts: [[String: String]] = subjects.map { s in
            [
                "id": s.id.uuidString,
                "name": s.name,
                "colorHex": s.colorHex,
                "isUserCreated": s.isUserCreated ? "true" : "false",
                "sortOrder": "\(s.sortOrder)",
            ]
        }
        
        try await supabase.from("users")
            .update(["subjects": subjectDicts])
            .eq("uid", value: uuid)
            .execute()
    }
    
    /// Sync study subjects from Supabase into SwiftData.
    /// Returns `true` if Supabase had subjects, `false` if not.
    @MainActor
    @discardableResult
    func syncSubjects(forUser uid: String, context: ModelContext) async -> Bool {
        do {
            guard let userRow = try await fetchUserProfile(uid: uid),
                  let subjectDicts = userRow.subjects,
                  !subjectDicts.isEmpty else {
                print("[SYNC] No subjects found in Supabase")
                return false
            }
            
            print("[SYNC] Found \(subjectDicts.count) subjects in Supabase")
            
            let descriptor = FetchDescriptor<StudySubject>()
            let localSubjects = (try? context.fetch(descriptor)) ?? []
            
            // Build a set of cloud subject names (lowercased) for dedup
            let cloudNameSet = Set(subjectDicts.compactMap { $0["name"]?.lowercased() })
            let cloudIDSet = Set(subjectDicts.compactMap { $0["id"] })
            
            // Remove local duplicates
            var removedDuplicates = 0
            for local in localSubjects {
                let localIDString = local.id.uuidString
                let localNameLower = local.name.lowercased()
                if cloudNameSet.contains(localNameLower) && !cloudIDSet.contains(localIDString) {
                    context.delete(local)
                    removedDuplicates += 1
                }
            }
            if removedDuplicates > 0 {
                print("[SYNC] Removed \(removedDuplicates) duplicate local subjects")
            }
            
            // Re-fetch after deletions
            let remainingSubjects = (try? context.fetch(descriptor)) ?? []
            let localIDSet = Set(remainingSubjects.map { $0.id.uuidString })
            
            var restoredCount = 0
            var updatedCount = 0
            
            for dict in subjectDicts {
                guard let idString = dict["id"],
                      let uuid = UUID(uuidString: idString) else { continue }
                
                let name = dict["name"] ?? "Unknown"
                let colorHex = dict["colorHex"] ?? "#888888"
                let isUserCreated = dict["isUserCreated"] == "true"
                let sortOrder = Int(dict["sortOrder"] ?? "0") ?? 0
                
                if localIDSet.contains(idString) {
                    if let existing = remainingSubjects.first(where: { $0.id == uuid }) {
                        existing.name = name
                        existing.colorHex = colorHex
                        existing.sortOrder = sortOrder
                        updatedCount += 1
                    }
                } else {
                    let subject = StudySubject(name: name, colorHex: colorHex, isUserCreated: isUserCreated, sortOrder: sortOrder)
                    subject.id = uuid
                    context.insert(subject)
                    restoredCount += 1
                    print("[SYNC] Restored subject: \(name) (\(colorHex))")
                }
            }
            print("[SYNC] Subjects: \(restoredCount) restored, \(updatedCount) updated")
            return true
        } catch {
            print("[SYNC] Subject sync FAILED: \(error)")
            return false
        }
    }
    
    // MARK: - Sync from Cloud
    
    /// Fetch all timelapses for a user from Supabase and merge into SwiftData.
    @MainActor
    func syncTimelapses(forUser uid: String, context: ModelContext) async {
        do {
            let rows = try await fetchTimelapses(forUser: uid, limit: 200)
            print("[SYNC] Found \(rows.count) timelapses in Supabase")
            
            let descriptor = FetchDescriptor<StudyTimelapse>()
            let localTimelapses = (try? context.fetch(descriptor)) ?? []
            let localIDSet = Set(localTimelapses.map { $0.id.uuidString })
            print("[SYNC] \(localTimelapses.count) timelapses already stored locally")
            
            var updatedCount = 0
            var insertedCount = 0
            var thumbDownloaded = 0
            
            for row in rows {
                let idString = row.id.uuidString
                
                if localIDSet.contains(idString) {
                    if let existing = localTimelapses.first(where: { $0.id == row.id }) {
                        existing.likeCount = row.likeCount
                        existing.likedByUIDs = row.likedByUids
                        existing.commentCount = row.commentCount
                        existing.videoDownloadURL = row.videoDownloadUrl
                        existing.thumbnailDownloadURL = row.thumbnailDownloadUrl
                        existing.authorAvatarURL = row.authorAvatarUrl
                        // Download thumbnail from cloud if missing locally
                        if existing.thumbnailData == nil,
                           let thumbURL = row.thumbnailDownloadUrl,
                           let thumbRemoteURL = URL(string: thumbURL) {
                            if let (thumbData, _) = try? await URLSession.shared.data(from: thumbRemoteURL) {
                                existing.thumbnailData = thumbData
                                thumbDownloaded += 1
                            }
                        }
                        updatedCount += 1
                    }
                } else {
                    let timelapse = StudyTimelapse(
                        authorID: row.authorId.uuidString,
                        authorName: row.authorName,
                        authorAvatarURL: row.authorAvatarUrl,
                        caption: row.caption,
                        studyDescription: row.studyDescription,
                        subject: row.subject,
                        durationSeconds: row.durationSeconds,
                        isLandscape: row.isLandscape
                    )
                    timelapse.id = row.id
                    timelapse.createdAt = row.createdAt
                    timelapse.likeCount = row.likeCount
                    timelapse.likedByUIDs = row.likedByUids
                    timelapse.commentCount = row.commentCount
                    timelapse.videoDownloadURL = row.videoDownloadUrl
                    timelapse.thumbnailDownloadURL = row.thumbnailDownloadUrl
                    // Download thumbnail from cloud
                    if let thumbURL = row.thumbnailDownloadUrl,
                       let thumbRemoteURL = URL(string: thumbURL) {
                        if let (thumbData, _) = try? await URLSession.shared.data(from: thumbRemoteURL) {
                            timelapse.thumbnailData = thumbData
                            thumbDownloaded += 1
                        }
                    }
                    
                    context.insert(timelapse)
                    insertedCount += 1
                    print("[SYNC] Restored timelapse: \(row.subject) - \"\(row.caption.prefix(30))\" (\(row.durationSeconds)s)")
                }
            }
            print("[SYNC] Timelapses: \(insertedCount) restored from cloud, \(updatedCount) updated, \(thumbDownloaded) thumbnails downloaded")
            
            // Sync comments for all timelapses that have comments
            let allTimelapses = (try? context.fetch(FetchDescriptor<StudyTimelapse>())) ?? []
            for tl in allTimelapses where tl.commentCount > 0 {
                await syncComments(forTimelapse: tl.id, context: context)
            }
        } catch {
            print("[SYNC] Timelapse sync FAILED: \(error)")
        }
    }
    
    /// Fetch user profile from Supabase and update or create local SwiftData profile.
    @MainActor
    func syncUserProfile(uid: String, context: ModelContext) async {
        print("[SYNC] Fetching user profile from Supabase...")
        var userRow: UserRow?
        do {
            userRow = try await fetchUserProfile(uid: uid)
            print("[SYNC] Supabase profile fetched")
        } catch {
            print("[SYNC] Supabase profile fetch failed (will use Auth info): \(error)")
        }
        
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        let existing = try? context.fetch(descriptor).first
        
        if let profile = existing {
            if let row = userRow {
                profile.displayName = row.displayName
                profile.email = row.email
                profile.bio = row.bio
                if let avatar = row.avatarUrl { profile.avatarURL = avatar }
                // Stats only ever increase — keep the higher value between local and cloud
                profile.totalStudyMinutes = max(profile.totalStudyMinutes, row.totalStudyMinutes)
                profile.streakDays = max(profile.streakDays, row.streakDays)
                profile.friendUIDs = row.friendUids
                
                // If local stats were higher, push them back to Supabase
                if profile.totalStudyMinutes > row.totalStudyMinutes || profile.streakDays > row.streakDays {
                    try? await saveUserProfile(profile)
                    print("[SYNC] Local stats were higher — pushed to Supabase")
                }
            }
            print("[SYNC] Updated existing local profile: \(profile.displayName)")
        } else {
            print("[SYNC] No local profile found — creating from cloud/Auth data...")
            let supabaseUser = supabase.auth.currentUser
            
            let displayName = userRow?.displayName
                ?? supabaseUser?.userMetadata["full_name"]?.stringValue
                ?? "Student"
            let email = userRow?.email
                ?? supabaseUser?.email
                ?? ""
            let bio = userRow?.bio ?? ""
            let avatarURL = userRow?.avatarUrl
                ?? supabaseUser?.userMetadata["avatar_url"]?.stringValue
            
            let profile = UserProfile(
                displayName: displayName,
                email: email,
                firebaseUID: uid,
                avatarURL: avatarURL,
                bio: bio
            )
            
            if let row = userRow {
                profile.totalStudyMinutes = row.totalStudyMinutes
                profile.streakDays = row.streakDays
                profile.friendUIDs = row.friendUids
                profile.joinDate = row.joinDate
            }
            
            context.insert(profile)
            try? context.save()
            print("[SYNC] Created new local profile: \(displayName)")
            
            // Save the profile to Supabase if we don't have cloud data yet
            if userRow == nil {
                try? await saveUserProfile(profile)
                print("[SYNC] Pushed new profile to Supabase (no cloud data existed)")
            }
        }
    }
}

// MARK: - JSON Value Helper

extension Supabase.AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        default: return nil
        }
    }
}
