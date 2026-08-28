//
//  SupabaseService.swift
//  Pigeon
//
//  Supabase database CRUD for users, timelapses, and comments
//

import Foundation
import Supabase
import SwiftData

// MARK: - Codable Row Types (map 1:1 to Supabase tables)

struct UserRow: Codable, Identifiable, Sendable {
    var id: UUID { uid }
    let uid: UUID
    var displayName: String
    var username: String?
    var email: String
    var avatarUrl: String?
    var bio: String
    var joinDate: Date
    var totalStudyMinutes: Int
    var streakDays: Int
    var friendUids: [String]
    var pendingFriendRequestUids: [String]
    var subjects: [[String: String]]?
    var lastSeenAt: Date?
    var isStudying: Bool?
    var currentSubject: String?
    var isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case uid
        case displayName = "display_name"
        case username
        case email
        case avatarUrl = "avatar_url"
        case bio
        case joinDate = "join_date"
        case totalStudyMinutes = "total_study_minutes"
        case streakDays = "streak_days"
        case friendUids = "friend_uids"
        case pendingFriendRequestUids = "pending_friend_request_uids"
        case subjects
        case lastSeenAt = "last_seen_at"
        case isStudying = "is_studying"
        case currentSubject = "current_subject"
        case isPrivate = "is_private"
    }
}

struct FriendRequestRow: Codable, Sendable {
    let id: UUID
    var senderUid: UUID
    var receiverUid: UUID
    var status: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderUid = "sender_uid"
        case receiverUid = "receiver_uid"
        case status
        case createdAt = "created_at"
    }
}

struct StudyGroupRow: Codable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var creatorUid: String
    var memberUids: [String]
    var iconName: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case creatorUid = "creator_uid"
        case memberUids = "member_uids"
        case iconName = "icon_name"
        case createdAt = "created_at"
    }
}

struct GroupInviteRow: Codable, Sendable {
    let id: UUID
    var groupId: UUID
    var inviterUid: String
    var inviteeUid: String
    var status: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case inviterUid = "inviter_uid"
        case inviteeUid = "invitee_uid"
        case status
        case createdAt = "created_at"
    }
}

struct TimelapseRow: Codable, Sendable {
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
    var appLeaveCount: Int?
    var offTaskSeconds: Int?
    var subjectSegmentsJson: String?
    
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
        case appLeaveCount = "app_leave_count"
        case offTaskSeconds = "off_task_seconds"
        case subjectSegmentsJson = "subject_segments_json"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorAvatarUrl, forKey: .authorAvatarUrl)
        try container.encode(caption, forKey: .caption)
        try container.encode(studyDescription, forKey: .studyDescription)
        try container.encode(subject, forKey: .subject)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isLandscape, forKey: .isLandscape)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(likedByUids, forKey: .likedByUids)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encodeIfPresent(videoDownloadUrl, forKey: .videoDownloadUrl)
        try container.encodeIfPresent(thumbnailDownloadUrl, forKey: .thumbnailDownloadUrl)
        // NOTE: appLeaveCount, offTaskSeconds, and subjectSegmentsJson
        // are intentionally omitted from encoding. They require matching
        // columns in the Supabase timelapses table. Once the columns are
        // added, uncomment the lines below.
        // try container.encodeIfPresent(appLeaveCount, forKey: .appLeaveCount)
        // try container.encodeIfPresent(offTaskSeconds, forKey: .offTaskSeconds)
        // try container.encodeIfPresent(subjectSegmentsJson, forKey: .subjectSegmentsJson)
    }
}

// MARK: - RPC Parameter Types

struct AddFriendParams: Codable, Sendable {
    let currentUid: UUID
    let friendUid: String
    
    enum CodingKeys: String, CodingKey {
        case currentUid = "current_uid"
        case friendUid = "friend_uid"
    }
}

struct RemoveFriendParams: Codable, Sendable {
    let currentUid: UUID
    let friendUid: String
    
    enum CodingKeys: String, CodingKey {
        case currentUid = "current_uid"
        case friendUid = "friend_uid"
    }
}

struct ToggleLikeParams: Codable, Sendable {
    let pTimelapseId: UUID
    let pUserUid: String
    let pIsLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case pTimelapseId = "p_timelapse_id"
        case pUserUid = "p_user_uid"
        case pIsLiked = "p_is_liked"
    }
}

// MARK: - Supabase Service

final class SupabaseService: Sendable {
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
            username: profile.username,
            email: profile.email,
            avatarUrl: profile.avatarURL,
            bio: profile.bio,
            joinDate: profile.joinDate,
            totalStudyMinutes: profile.totalStudyMinutes,
            streakDays: profile.streakDays,
            friendUids: profile.friendUIDs,
            pendingFriendRequestUids: profile.pendingFriendRequestUIDs,
            isPrivate: profile.isPrivate
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
    
    /// Search users by display name or @username prefix (case-insensitive).
    func searchUsers(query: String, limit: Int = 20) async throws -> [UserRow] {
        let cleaned = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let response: [UserRow] = try await supabase.from("users")
            .select()
            .or("display_name.ilike.\(cleaned)%,username.ilike.\(cleaned)%")
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Timelapses
    
    /// Save a timelapse to Supabase.
    func saveTimelapse(_ timelapse: StudyTimelapse) async throws {
        guard let authorUUID = UUID(uuidString: timelapse.authorID) else {
            print("[SYNC] ERROR: Invalid authorID '\(timelapse.authorID)' — cannot save timelapse \(timelapse.id)")
            throw NSError(domain: "SupabaseService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid authorID: \(timelapse.authorID)"
            ])
        }
        
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
            thumbnailDownloadUrl: timelapse.thumbnailDownloadURL,
            appLeaveCount: timelapse.appLeaveCount,
            offTaskSeconds: timelapse.offTaskSeconds,
            subjectSegmentsJson: timelapse.subjectSegmentsJSON
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
    
    /// Fetch timelapses for a specific user (paginated to get ALL records).
    func fetchTimelapses(forUser uid: String, limit: Int? = nil) async throws -> [TimelapseRow] {
        guard let uuid = UUID(uuidString: uid) else { return [] }

        // If a specific limit is given, use a single fetch
        if let limit {
            let response: [TimelapseRow] = try await supabase.from("timelapses")
                .select()
                .eq("author_id", value: uuid)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return response
        }

        // Otherwise paginate to fetch ALL timelapses (Supabase default max is 1000 per request)
        let pageSize = 1000
        var allRows: [TimelapseRow] = []
        var offset = 0

        while true {
            let page: [TimelapseRow] = try await supabase.from("timelapses")
                .select()
                .eq("author_id", value: uuid)
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            allRows.append(contentsOf: page)

            if page.count < pageSize {
                break // Last page — we got everything
            }
            offset += pageSize
        }

        return allRows
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

    /// Fetch recent timelapses from public accounts (for the public feed).
    func fetchPublicFeed(excludeUID: String, limit: Int = 50) async throws -> [TimelapseRow] {
        // Get public user UIDs (all users are public unless is_private is set)
        let publicUsers: [UserRow] = try await supabase.from("users")
            .select()
            .neq("uid", value: UUID(uuidString: excludeUID) ?? UUID())
            .execute()
            .value

        let publicUIDs = publicUsers.map { $0.uid }
        guard !publicUIDs.isEmpty else { return [] }

        let response: [TimelapseRow] = try await supabase.from("timelapses")
            .select()
            .in("author_id", values: publicUIDs)
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
    
    // MARK: - Usernames
    
    /// Check if a username is available.
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let result: Bool = try await supabase.rpc(
            "is_username_available",
            params: ["p_username": username.lowercased()]
        ).execute().value
        return result
    }
    
    /// Claim a username atomically (returns false if taken).
    func claimUsername(_ username: String, forUser uid: String) async throws -> Bool {
        guard let uuid = UUID(uuidString: uid) else { return false }
        let result: Bool = try await supabase.rpc(
            "claim_username",
            params: ["p_uid": uuid.uuidString, "p_username": username.lowercased()]
        ).execute().value
        return result
    }
    
    // MARK: - Presence / Online Status
    
    /// Update the user's online presence (last seen timestamp + optional study status).
    func updatePresence(uid: String, isStudying: Bool, currentSubject: String?) async {
        guard let uuid = UUID(uuidString: uid) else { return }
        struct PresenceUpdate: Codable {
            let lastSeenAt: Date
            let isStudying: Bool
            let currentSubject: String?
            
            enum CodingKeys: String, CodingKey {
                case lastSeenAt = "last_seen_at"
                case isStudying = "is_studying"
                case currentSubject = "current_subject"
            }
        }
        let update = PresenceUpdate(
            lastSeenAt: Date(),
            isStudying: isStudying,
            currentSubject: currentSubject
        )
        _ = try? await supabase.from("users")
            .update(update)
            .eq("uid", value: uuid)
            .execute()
    }
    
    /// Mark user as offline (no longer studying, update last seen).
    func clearPresence(uid: String) async {
        await updatePresence(uid: uid, isStudying: false, currentSubject: nil)
    }
    
    /// Fetch multiple user profiles by UIDs.
    func fetchUserProfiles(uids: [String]) async throws -> [UserRow] {
        guard !uids.isEmpty else { return [] }
        let uuids = uids.compactMap { UUID(uuidString: $0) }
        let response: [UserRow] = try await supabase.from("users")
            .select()
            .in("uid", values: uuids)
            .execute()
            .value
        return response
    }
    
    // MARK: - Friend Requests
    
    /// Send a friend request.
    func sendFriendRequest(from senderUID: String, to receiverUID: String) async throws {
        guard let senderUUID = UUID(uuidString: senderUID),
              let receiverUUID = UUID(uuidString: receiverUID) else { return }
        let row = FriendRequestRow(
            id: UUID(),
            senderUid: senderUUID,
            receiverUid: receiverUUID,
            status: "pending",
            createdAt: Date()
        )
        try await supabase.from("friend_requests").upsert(row).execute()
    }
    
    /// Fetch pending friend requests received by this user.
    func fetchPendingFriendRequests(forUser uid: String) async throws -> [FriendRequestRow] {
        guard let uuid = UUID(uuidString: uid) else { return [] }
        let response: [FriendRequestRow] = try await supabase.from("friend_requests")
            .select()
            .eq("receiver_uid", value: uuid)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }
    
    /// Fetch pending friend requests sent by this user.
    func fetchSentFriendRequests(forUser uid: String) async throws -> [FriendRequestRow] {
        guard let uuid = UUID(uuidString: uid) else { return [] }
        let response: [FriendRequestRow] = try await supabase.from("friend_requests")
            .select()
            .eq("sender_uid", value: uuid)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }
    
    /// Accept a friend request (atomic RPC — adds to both users' friend lists).
    func acceptFriendRequest(requestID: UUID) async throws {
        try await supabase.rpc(
            "accept_friend_request",
            params: ["request_id": requestID.uuidString]
        ).execute()
    }
    
    /// Decline a friend request.
    func declineFriendRequest(requestID: UUID) async throws {
        try await supabase.from("friend_requests")
            .update(["status": "declined"])
            .eq("id", value: requestID)
            .execute()
    }
    
    // MARK: - Study Groups
    
    /// Create a new study group.
    func createStudyGroup(_ group: StudyGroup) async throws {
        let row = StudyGroupRow(
            id: group.id,
            name: group.name,
            description: group.groupDescription,
            creatorUid: group.creatorID,
            memberUids: group.memberIDs,
            iconName: group.iconName,
            createdAt: group.createdAt
        )
        try await supabase.from("study_groups").insert(row).execute()
    }
    
    /// Fetch groups the user belongs to.
    func fetchGroups(forUser uid: String) async throws -> [StudyGroupRow] {
        let response: [StudyGroupRow] = try await supabase.from("study_groups")
            .select()
            .contains("member_uids", value: [uid])
            .execute()
            .value
        return response
    }
    
    /// Invite a user to a group.
    func inviteToGroup(groupID: UUID, inviterUID: String, inviteeUID: String) async throws {
        let row = GroupInviteRow(
            id: UUID(),
            groupId: groupID,
            inviterUid: inviterUID,
            inviteeUid: inviteeUID,
            status: "pending",
            createdAt: Date()
        )
        try await supabase.from("group_invites").upsert(row).execute()
    }
    
    /// Fetch pending group invites for a user.
    func fetchGroupInvites(forUser uid: String) async throws -> [GroupInviteRow] {
        let response: [GroupInviteRow] = try await supabase.from("group_invites")
            .select()
            .eq("invitee_uid", value: uid)
            .eq("status", value: "pending")
            .execute()
            .value
        return response
    }
    
    /// Accept a group invite.
    func acceptGroupInvite(inviteID: UUID, groupID: UUID, userUID: String) async throws {
        try await supabase.rpc(
            "join_group",
            params: ["p_group_id": groupID.uuidString, "p_user_uid": userUID]
        ).execute()
        try await supabase.from("group_invites")
            .update(["status": "accepted"])
            .eq("id", value: inviteID)
            .execute()
    }
    
    /// Leave a group.
    func leaveGroup(groupID: UUID, userUID: String) async throws {
        try await supabase.rpc(
            "leave_group",
            params: ["p_group_id": groupID.uuidString, "p_user_uid": userUID]
        ).execute()
    }
    
    /// Delete a group (creator only).
    func deleteGroup(id: UUID) async throws {
        try await supabase.from("study_groups")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    /// Fetch leaderboard data for group members sorted by study time.
    func fetchGroupLeaderboard(memberUIDs: [String]) async throws -> [UserRow] {
        guard !memberUIDs.isEmpty else { return [] }
        let uuids = memberUIDs.compactMap { UUID(uuidString: $0) }
        let response: [UserRow] = try await supabase.from("users")
            .select()
            .in("uid", values: uuids)
            .order("total_study_minutes", ascending: false)
            .execute()
            .value
        return response
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
    /// Performs a full replacement: local subjects are replaced by the cloud set
    /// so switching accounts always shows the correct subjects.
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
            
            // Build lookup of cloud subjects by ID
            let cloudIDSet = Set(subjectDicts.compactMap { $0["id"] })
            
            // Remove ALL local subjects that aren't in the cloud set.
            // This ensures switching accounts doesn't leave stale subjects behind.
            var removedCount = 0
            for local in localSubjects {
                if !cloudIDSet.contains(local.id.uuidString) {
                    context.delete(local)
                    removedCount += 1
                }
            }
            if removedCount > 0 {
                print("[SYNC] Removed \(removedCount) local subjects not in cloud")
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
            // Retry any pending cloud deletes before syncing
            let pendingDeletes = PendingDeleteStore.ids()
            for idString in pendingDeletes {
                if let uuid = UUID(uuidString: idString) {
                    do {
                        try await deleteTimelapse(uuid)
                        PendingDeleteStore.remove(uuid)
                        print("[SYNC] Retried pending delete for \(idString.prefix(8))")
                    } catch {
                        print("[SYNC] Pending delete retry failed for \(idString.prefix(8)): \(error)")
                    }
                }
            }
            
            let rows = try await fetchTimelapses(forUser: uid)
            print("[SYNC] Found \(rows.count) timelapses in Supabase")
            
            let descriptor = FetchDescriptor<StudyTimelapse>()
            let localTimelapses = (try? context.fetch(descriptor)) ?? []
            let localIDSet = Set(localTimelapses.map { $0.id.uuidString })
            print("[SYNC] \(localTimelapses.count) timelapses already stored locally")
            
            var updatedCount = 0
            var insertedCount = 0
            
            // Collect timelapses needing thumbnail downloads
            var thumbDownloads: [(timelapse: StudyTimelapse, url: URL)] = []
            
            for row in rows {
                let idString = row.id.uuidString
                
                // Skip any timelapse that was locally deleted
                if PendingDeleteStore.contains(row.id) {
                    print("[SYNC] Skipping deleted timelapse \(idString.prefix(8))")
                    continue
                }
                
                if localIDSet.contains(idString) {
                    if let existing = localTimelapses.first(where: { $0.id == row.id }) {
                        // Only sync social/engagement fields from cloud — never overwrite
                        // core study data (duration, subject, caption, etc.) which is
                        // authoritative from the device that recorded the session.
                        existing.likeCount = max(existing.likeCount, row.likeCount)
                        existing.likedByUIDs = row.likedByUids
                        existing.commentCount = max(existing.commentCount, row.commentCount)
                        // Only fill in download URLs if local doesn't have them
                        if existing.videoDownloadURL == nil {
                            existing.videoDownloadURL = row.videoDownloadUrl
                        }
                        if existing.thumbnailDownloadURL == nil {
                            existing.thumbnailDownloadURL = row.thumbnailDownloadUrl
                        }
                        existing.authorAvatarURL = row.authorAvatarUrl
                        // Sync app leaves and subject segments from cloud only if local has defaults
                        if let cloudLeaves = row.appLeaveCount, existing.appLeaveCount == 0, cloudLeaves > 0 {
                            existing.appLeaveCount = cloudLeaves
                        }
                        if let cloudOffTask = row.offTaskSeconds, existing.offTaskSeconds == 0, cloudOffTask > 0 {
                            existing.offTaskSeconds = cloudOffTask
                        }
                        if let cloudSegments = row.subjectSegmentsJson, existing.subjectSegmentsJSON == nil {
                            existing.subjectSegmentsJSON = cloudSegments
                        }
                        existing.cloudSynced = true  // confirmed in cloud
                        // Queue thumbnail download if missing locally
                        if existing.thumbnailData == nil,
                           let thumbURL = row.thumbnailDownloadUrl,
                           let thumbRemoteURL = URL(string: thumbURL) {
                            thumbDownloads.append((existing, thumbRemoteURL))
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
                    timelapse.appLeaveCount = row.appLeaveCount ?? 0
                    timelapse.offTaskSeconds = row.offTaskSeconds ?? 0
                    timelapse.subjectSegmentsJSON = row.subjectSegmentsJson
                    // Queue thumbnail download
                    if let thumbURL = row.thumbnailDownloadUrl,
                       let thumbRemoteURL = URL(string: thumbURL) {
                        thumbDownloads.append((timelapse, thumbRemoteURL))
                    }
                    
                    timelapse.cloudSynced = true  // came from cloud, so it's synced
                    context.insert(timelapse)
                    insertedCount += 1
                    print("[SYNC] Restored timelapse: \(row.subject) - \"\(row.caption.prefix(30))\" (\(row.durationSeconds)s)")
                }
            }
            
            // Download thumbnails in parallel (max 4 concurrent)
            var thumbDownloaded = 0
            if !thumbDownloads.isEmpty {
                await withTaskGroup(of: (Int, Data?).self) { group in
                    for (index, task) in thumbDownloads.enumerated() {
                        group.addTask {
                            let data = try? await URLSession.shared.data(from: task.url).0
                            return (index, data)
                        }
                        // Limit concurrency to 4
                        if (index + 1) % 4 == 0, let result = await group.next() {
                            if let data = result.1 {
                                thumbDownloads[result.0].timelapse.thumbnailData = data
                                thumbDownloaded += 1
                            }
                        }
                    }
                    // Collect remaining results
                    for await result in group {
                        if let data = result.1 {
                            thumbDownloads[result.0].timelapse.thumbnailData = data
                            thumbDownloaded += 1
                        }
                    }
                }
            }
            print("[SYNC] Timelapses: \(insertedCount) restored from cloud, \(updatedCount) updated, \(thumbDownloaded) thumbnails downloaded")
            
            // Push any local sessions that aren't on Supabase yet (catches failed uploads,
            // app kills during upload, or sessions created while offline)
            let cloudIDSet = Set(rows.map { $0.id.uuidString })
            let allLocalAfterSync = (try? context.fetch(FetchDescriptor<StudyTimelapse>())) ?? []
            let unsyncedLocal = allLocalAfterSync.filter {
                $0.authorID == uid && !cloudIDSet.contains($0.id.uuidString)
            }
            if !unsyncedLocal.isEmpty {
                var uploadedCount = 0
                for timelapse in unsyncedLocal {
                    do {
                        // Upload thumbnail if we have data but no cloud URL
                        if timelapse.thumbnailDownloadURL == nil, let thumbData = timelapse.thumbnailData {
                            let thumbURL = try await StorageService.shared.uploadThumbnail(
                                data: thumbData, userUID: timelapse.authorID, timelapseID: timelapse.id.uuidString
                            )
                            timelapse.thumbnailDownloadURL = thumbURL
                        }
                        try await saveTimelapse(timelapse)
                        timelapse.cloudSynced = true
                        uploadedCount += 1
                    } catch {
                        print("[SYNC] Failed to push local session \(timelapse.id.uuidString.prefix(8)): \(error)")
                    }
                }
                print("[SYNC] Pushed \(uploadedCount)/\(unsyncedLocal.count) unsynced local sessions to Supabase")
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
                profile.username = row.username
                if let privacy = row.isPrivate { profile.isPrivate = privacy }

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
                username: userRow?.username,
                avatarURL: avatarURL,
                bio: bio
            )
            
            if let row = userRow {
                profile.totalStudyMinutes = row.totalStudyMinutes
                profile.streakDays = row.streakDays
                profile.friendUIDs = row.friendUids
                profile.joinDate = row.joinDate
                if let privacy = row.isPrivate { profile.isPrivate = privacy }
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
