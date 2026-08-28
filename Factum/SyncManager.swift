//
//  SyncManager.swift
//  Pigeon
//
//  Reliable cloud sync with automatic retries and exponential backoff.
//  Ensures study sessions are never lost even under poor network conditions.
//

import Foundation
import SwiftData

@MainActor
final class SyncManager {
    static let shared = SyncManager()
    
    /// Maximum number of immediate retries per upload attempt (with backoff).
    private let maxImmediateRetries = 3
    
    /// Maximum retry count per app-launch cycle. Resets on each cold launch
    /// so sessions are never permanently abandoned.
    private let maxRetriesPerCycle = 5
    
    /// Whether a retry pass is currently running (prevents overlapping runs).
    private var isRetrying = false
    
    private init() {}
    
    // MARK: - Upload a New Session (called from PostCaptionView)
    
    /// Uploads a freshly-created timelapse to Supabase with built-in retry.
    /// This replaces the old fire-and-forget Task.detached in PostCaptionView.
    func uploadSession(
        _ timelapse: StudyTimelapse,
        videoURL: URL?,
        context: ModelContext
    ) {
        // Capture all value-type data needed off the main actor BEFORE detaching.
        let uid = timelapse.authorID
        let timelapseID = timelapse.id.uuidString
        let thumbData = timelapse.thumbnailData
        let videoLocalURL = videoURL
        
        Task.detached { [weak self] in
            guard let self else { return }
            
            // Step 1: Upload thumbnail
            await self.uploadThumbnailWithRetry(
                thumbData: thumbData, uid: uid, timelapseID: timelapseID,
                timelapse: timelapse, context: context
            )
            
            // Step 2: Upload video
            await self.uploadVideoWithRetry(
                videoURL: videoLocalURL, uid: uid, timelapseID: timelapseID,
                timelapse: timelapse, context: context
            )
            
            // Step 3: Save the session record (this is the critical step)
            await self.uploadRecordWithRetry(
                timelapse: timelapse, context: context
            )
            
            // Step 4: Sync user profile stats
            await self.syncUserStats(uid: uid, context: context)
        }
    }
    
    // MARK: - Recover Interrupted Session
    
    /// Checks for an interrupted session snapshot on disk and recovers it
    /// by creating a StudyTimelapse record and syncing it to the cloud.
    /// Returns a description string if a session was recovered, nil otherwise.
    func recoverInterruptedSession(uid: String, context: ModelContext) async -> String? {
        guard let snapshot = SessionSnapshot.load() else { return nil }
        
        // Always recover — no time or duration thresholds.
        // The user's study time is sacred and should never be silently discarded.
        
        // Check if we already recovered this session (by matching start date within 5s)
        let descriptor = FetchDescriptor<StudyTimelapse>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let alreadyRecovered = existing.contains { timelapse in
            timelapse.authorID == uid &&
            abs(timelapse.createdAt.timeIntervalSince(snapshot.startDate)) < 5
        }
        if alreadyRecovered {
            SessionSnapshot.clear()
            print("[RECOVERY] Session already exists locally — clearing snapshot")
            return nil
        }
        
        // Build subject segments
        let segments: [SubjectSegment] = snapshot.subjectSegments.map {
            SubjectSegment(subject: $0.subject, seconds: $0.seconds)
        }
        let primarySubject = segments.max(by: { $0.seconds < $1.seconds })?.subject ?? snapshot.currentSubject
        
        // Look up current user info
        let userDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        let user = try? context.fetch(userDescriptor).first
        
        // Create the recovered timelapse
        let timelapse = StudyTimelapse(
            authorID: uid,
            authorName: user?.displayName ?? "You",
            authorAvatarURL: user?.avatarURL,
            caption: "Recovered session",
            studyDescription: "This session was interrupted and automatically recovered.",
            subject: primarySubject,
            durationSeconds: snapshot.studySeconds
        )
        timelapse.createdAt = snapshot.startDate
        timelapse.isLandscape = snapshot.isLandscape
        if segments.count > 1 {
            timelapse.subjectSegments = segments
        }
        
        // Save locally
        context.insert(timelapse)
        
        // Update user stats
        if let user {
            user.totalStudyMinutes += snapshot.studySeconds / 60
        }
        try? context.save()
        
        // Sync to cloud
        uploadSession(timelapse, videoURL: nil, context: context)
        
        // Clear the snapshot — it's been recovered
        SessionSnapshot.clear()
        
        let minutes = snapshot.studySeconds / 60
        let description = "\(minutes) min of \(primarySubject)"
        print("[RECOVERY] ✓ Recovered interrupted session: \(description)")
        return description
    }
    
    // MARK: - Retry Unsynced Sessions (called on app launch + foreground)
    
    /// Finds all unsynced sessions and attempts to upload them.
    /// On each app launch, retry counts are reset so sessions get fresh attempts.
    func retryUnsyncedSessions(uid: String, context: ModelContext) async {
        guard !isRetrying else {
            print("[SYNC] Retry already in progress, skipping")
            return
        }
        isRetrying = true
        defer { isRetrying = false }
        
        let descriptor = FetchDescriptor<StudyTimelapse>()
        let allLocal = (try? context.fetch(descriptor)) ?? []
        let unsynced = allLocal.filter { $0.authorID == uid && !$0.cloudSynced }
        
        guard !unsynced.isEmpty else {
            print("[SYNC] All local sessions are cloud-synced")
            return
        }
        
        // Process up to 5 sessions per cycle to avoid connection saturation
        let batchSize = 5
        let batch = Array(unsynced.prefix(batchSize))
        print("[SYNC] Found \(unsynced.count) unsynced sessions — uploading batch of \(batch.count)...")
        var uploaded = 0
        var consecutiveFailures = 0
        
        for timelapse in batch {
            // Stop early if we hit 3 consecutive failures (likely a network issue)
            if consecutiveFailures >= 3 {
                print("[SYNC] Stopping after 3 consecutive failures — will retry next cycle")
                break
            }
            
            timelapse.lastSyncAttempt = Date()
            timelapse.syncRetryCount += 1
            
            do {
                // Upload thumbnail if needed
                if timelapse.thumbnailDownloadURL == nil, let thumbData = timelapse.thumbnailData {
                    do {
                        let thumbURL = try await StorageService.shared.uploadThumbnail(
                            data: thumbData, userUID: timelapse.authorID, timelapseID: timelapse.id.uuidString
                        )
                        timelapse.thumbnailDownloadURL = thumbURL
                    } catch {
                        print("[SYNC] Thumbnail upload failed for \(timelapse.id.uuidString.prefix(8)): \(error.localizedDescription)")
                        // Non-fatal — continue with record upload
                    }
                }
                
                // Upload video if needed and local file still exists
                if timelapse.videoDownloadURL == nil, let videoURL = timelapse.videoURL, videoURL.isFileURL {
                    do {
                        let downloadURL = try await StorageService.shared.uploadVideo(
                            localURL: videoURL, userUID: timelapse.authorID, timelapseID: timelapse.id.uuidString
                        )
                        timelapse.videoDownloadURL = downloadURL
                    } catch {
                        print("[SYNC] Video upload failed for \(timelapse.id.uuidString.prefix(8)): \(error.localizedDescription)")
                        // Non-fatal — continue with record upload
                    }
                }
                
                // Save the session record (critical step)
                try await SupabaseService.shared.saveTimelapse(timelapse)
                timelapse.cloudSynced = true
                timelapse.syncRetryCount = 0
                uploaded += 1
                consecutiveFailures = 0
                print("[SYNC] ✓ Synced session \(timelapse.id.uuidString.prefix(8)) (attempt #\(timelapse.syncRetryCount))")
                
                // Small delay between uploads to avoid overwhelming the connection
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                consecutiveFailures += 1
                print("[SYNC] ✗ Failed session \(timelapse.id.uuidString.prefix(8)) (attempt #\(timelapse.syncRetryCount)): \(error)")
                
                // Longer delay after a failure before trying the next one
                try? await Task.sleep(for: .seconds(2))
            }
        }
        
        if uploaded > 0 {
            try? context.save()
            let remaining = unsynced.count - uploaded
            print("[SYNC] Batch complete: uploaded \(uploaded)/\(batch.count), \(remaining) still unsynced")
            
            // Push updated user stats
            let profileDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
            if let profile = try? context.fetch(profileDescriptor).first {
                try? await SupabaseService.shared.saveUserProfile(profile)
            }
        } else {
            try? context.save() // persist updated retry counts
        }
    }
    
    // MARK: - Private Helpers
    
    /// Exponential backoff: 2^retryCount seconds, capped at 60 seconds.
    /// Kept short so sessions sync within a few minutes at most.
    private func backoffInterval(for retryCount: Int) -> TimeInterval {
        min(pow(2.0, Double(min(retryCount, 6))), 60)
    }
    
    /// Retry a throwing async operation with exponential backoff.
    private func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = initialDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError!
    }
    
    private func uploadThumbnailWithRetry(
        thumbData: Data?, uid: String, timelapseID: String,
        timelapse: StudyTimelapse, context: ModelContext
    ) async {
        guard let thumbData else { return }
        do {
            let thumbURL = try await withRetry {
                try await StorageService.shared.uploadThumbnail(
                    data: thumbData, userUID: uid, timelapseID: timelapseID
                )
            }
            await MainActor.run {
                timelapse.thumbnailDownloadURL = thumbURL
                try? context.save()
            }
        } catch {
            print("[SYNC] Thumbnail upload failed after \(maxImmediateRetries) attempts: \(error.localizedDescription)")
        }
    }
    
    private func uploadVideoWithRetry(
        videoURL: URL?, uid: String, timelapseID: String,
        timelapse: StudyTimelapse, context: ModelContext
    ) async {
        guard let videoURL else { return }
        do {
            let downloadURL = try await withRetry {
                try await StorageService.shared.uploadVideo(
                    localURL: videoURL, userUID: uid, timelapseID: timelapseID
                )
            }
            await MainActor.run {
                timelapse.videoDownloadURL = downloadURL
                try? context.save()
            }
        } catch {
            print("[SYNC] Video upload failed after \(maxImmediateRetries) attempts: \(error.localizedDescription)")
        }
    }
    
    private func uploadRecordWithRetry(
        timelapse: StudyTimelapse, context: ModelContext
    ) async {
        // Build the Sendable row on the main actor so we don't capture @Model in @Sendable closure
        let row: TimelapseRow? = await MainActor.run {
            guard let authorUUID = UUID(uuidString: timelapse.authorID) else { return nil }
            return TimelapseRow(
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
        }
        guard let row else {
            print("[SYNC] ERROR: Invalid authorID — cannot save timelapse record")
            return
        }
        
        do {
            try await withRetry {
                try await SupabaseService.shared.saveTimelapseRow(row)
            }
            await MainActor.run {
                timelapse.cloudSynced = true
                try? context.save()
            }
            print("[SYNC] ✓ Timelapse record saved to Supabase")
        } catch {
            await MainActor.run {
                timelapse.syncRetryCount += 1
                timelapse.lastSyncAttempt = Date()
                try? context.save()
            }
            print("[SYNC] Timelapse record save FAILED after \(maxImmediateRetries) attempts (will retry on foreground): \(error.localizedDescription)")
        }
    }
    
    private func syncUserStats(uid: String, context: ModelContext) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
            if let user = try? context.fetch(descriptor).first {
                Task {
                    try? await SupabaseService.shared.saveUserProfile(user)
                }
            }
        }
    }
}
