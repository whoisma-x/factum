//
//  ContentView.swift
//  Factum
//
//  Created by Max on 7/11/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Binding var deepLinkTimelapseID: String?
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query private var users: [UserProfile]
    @State private var selectedTab = 0
    @State private var showCamera = false
    @State private var showOnboarding = false
    @State private var hasResolvedAuth = false
    @State private var deepLinkTimelapse: StudyTimelapse?
    @Namespace private var tabBarNamespace
    /// 0 = system, 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var showTutorial = false
    @State private var showCameraTutorial = false
    @State private var tabBarFrame: CGRect = .zero
    @State private var statsCardFrame: CGRect = .zero
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if hasResolvedAuth {
                // Content area
                Group {
                    switch selectedTab {
                    case 0: FeedView()
                    case 1: FriendsView()
                    case 3: GroupsView()
                    case 4: ProfileView()
                    default: FeedView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.bottom, 80)
                .onPreferenceChange(StatsCardFrameKey.self) { statsCardFrame = $0 }
                
                // Floating Liquid Glass tab bar
                customTabBar
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    tabBarFrame = geo.frame(in: .global)
                                }
                                .onChange(of: geo.size) {
                                    tabBarFrame = geo.frame(in: .global)
                                }
                        }
                    )
                    .padding(.bottom, 2)
                    .padding(.horizontal, 16)
                
                // Tutorial coach marks overlay (shown once after first sign-in)
                if showTutorial {
                    TutorialOverlayView(
                        isShowing: $showTutorial,
                        selectedTab: $selectedTab,
                        showCameraTutorial: $showCameraTutorial,
                        tabBarFrame: tabBarFrame,
                        statsCardFrame: statsCardFrame
                    )
                    .zIndex(100)
                    .onChange(of: showTutorial) { _, showing in
                        if !showing {
                            hasSeenTutorial = true
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FactumTheme.background)
        .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
        .fullScreenCover(isPresented: $showCamera) {
            TimelapseCameraView(isTutorialMode: showCameraTutorial) {
                // Camera tutorial finished — dismiss camera, then TutorialOverlayView
                // picks up the showCameraTutorial change to resume at profile step
                showCamera = false
                showCameraTutorial = false
            }
        }
        .onChange(of: showCameraTutorial) { _, isTutorial in
            if isTutorial {
                showCamera = true
            }
        }
        .sheet(item: $deepLinkTimelapse) { timelapse in
            TimelapseDetailView(timelapse: timelapse)
        }
        .onChange(of: deepLinkTimelapseID) { _, newID in
            guard let newID, let uuid = UUID(uuidString: newID) else { return }
            if let timelapse = allTimelapses.first(where: { $0.id == uuid }) {
                selectedTab = 0
                deepLinkTimelapse = timelapse
            }
            deepLinkTimelapseID = nil
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
            .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
        }
        .task {
            // Wait for Supabase to finish checking auth state
            while authService.isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if authService.isSignedIn {
                hasResolvedAuth = true
                await syncFromCloud()
                seedDemoDataIfNeeded()
            } else {
                showOnboarding = true
                hasResolvedAuth = true
            }
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if signedIn {
                showOnboarding = false
                hasResolvedAuth = true
                Task {
                    await syncFromCloud()
                    seedDemoDataIfNeeded()
                    if !hasSeenTutorial {
                        try? await Task.sleep(for: .milliseconds(800))
                        showTutorial = true
                    }
                }
            } else if !authService.isLoading {
                showOnboarding = true
            }
        }
    }
    
    private var currentUserAvatarURL: String? {
        let uid = authService.currentUserID
        return users.first { $0.firebaseUID == uid }?.avatarURL
    }
    
    private var tabBarAvatarImage: UIImage? {
        guard let avatarURL = currentUserAvatarURL,
              let url = URL(string: avatarURL),
              url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    // MARK: - Custom Tab Bar
    
    private let tabs: [(icon: String, tag: Int)] = [
        ("house.fill", 0),
        ("person.2.fill", 1),    // Friends
        ("video.fill", 2),       // Record (center)
        ("person.3.fill", 3),    // Groups
        ("person.circle.fill", 4),
    ]
    
    private var customTabBar: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tag) { tab in
                    if tab.tag == 2 {
                        // Center record button
                        Button {
                            Haptics.medium()
                            showCamera = true
                        } label: {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(FactumTheme.primaryText)
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    } else if tab.tag == 4, let avatarImage = tabBarAvatarImage {
                        // Profile tab with user's avatar
                        Button {
                            Haptics.light()
                            withAnimation(.smooth(duration: 0.3)) {
                                selectedTab = tab.tag
                            }
                        } label: {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedTab == tab.tag ? FactumTheme.primaryText : .clear,
                                            lineWidth: 2
                                        )
                                )
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if selectedTab == tab.tag {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(FactumTheme.primaryText.opacity(0.15))
                                            .matchedGeometryEffect(id: "activeTab", in: tabBarNamespace)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            Haptics.light()
                            withAnimation(.smooth(duration: 0.3)) {
                                selectedTab = tab.tag
                            }
                        } label: {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(
                                    selectedTab == tab.tag
                                    ? FactumTheme.primaryText
                                    : FactumTheme.secondaryText
                                )
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if selectedTab == tab.tag {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(FactumTheme.primaryText.opacity(0.15))
                                            .matchedGeometryEffect(id: "activeTab", in: tabBarNamespace)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
    }
    
    // MARK: - Local Setup
    
    @MainActor
    private func seedDemoDataIfNeeded() {
        let uid = authService.currentUserID
        guard !uid.isEmpty else { return }
        let profile = users.first { $0.firebaseUID == uid }
        let name = profile?.displayName ?? "Demo User"
        let email = profile?.email ?? ""
        SampleData.seedDemoDataIfNeeded(authorID: uid, authorName: name, email: email, context: modelContext)
    }

    private func syncFromCloud() async {
        let uid = authService.currentUserID
        guard !uid.isEmpty else {
            StudySubject.seedDefaultsIfNeeded(context: modelContext)
            return
        }
        
        // Sync user profile from Supabase (creates local profile if needed)
        await SupabaseService.shared.syncUserProfile(uid: uid, context: modelContext)
        
        // One-time migration: the first user to log in on this device gets
        // their local subjects pushed to Supabase. This preserves subjects
        // created before cloud sync existed. Runs once per device.
        let migrationKey = "factum_subjects_pushed_to_cloud"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.set(true, forKey: migrationKey)
            let preDescriptor = FetchDescriptor<StudySubject>()
            let localSubjects = (try? modelContext.fetch(preDescriptor)) ?? []
            if !localSubjects.isEmpty {
                // Only push if cloud has no subjects yet (don't overwrite existing cloud data)
                let profile = try? await SupabaseService.shared.fetchUserProfile(uid: uid)
                if (profile?.subjects ?? []).isEmpty {
                    try? await SupabaseService.shared.saveSubjects(localSubjects, forUser: uid)
                    print("[SYNC] Migration: pushed \(localSubjects.count) local subjects to Supabase for \(uid)")
                }
            }
        }

        // Sync study subjects from Supabase (full replacement of local subjects).
        // If cloud has subjects, they completely replace whatever is local.
        // If cloud has no subjects, seed defaults locally and push them.
        let hadCloudSubjects = await SupabaseService.shared.syncSubjects(forUser: uid, context: modelContext)
        if !hadCloudSubjects {
            // Delete any leftover subjects from other accounts
            let staleDescriptor = FetchDescriptor<StudySubject>()
            let staleSubjects = (try? modelContext.fetch(staleDescriptor)) ?? []
            for s in staleSubjects { modelContext.delete(s) }

            // Seed fresh defaults for this account
            StudySubject.seedDefaultsIfNeeded(context: modelContext)
            let subjectDescriptor = FetchDescriptor<StudySubject>()
            let seededSubjects = (try? modelContext.fetch(subjectDescriptor)) ?? []
            if !seededSubjects.isEmpty {
                try? await SupabaseService.shared.saveSubjects(seededSubjects, forUser: uid)
                print("[SYNC] Pushed \(seededSubjects.count) default subjects to Supabase")
            }
        }
        
        // Sync timelapse session records from Supabase (restores study history)
        print("[SYNC] Starting timelapse sync for uid: \(uid)")
        await SupabaseService.shared.syncTimelapses(forUser: uid, context: modelContext)
        
        // Verify what we have locally after sync
        let checkDescriptor = FetchDescriptor<StudyTimelapse>()
        let allLocal = (try? modelContext.fetch(checkDescriptor)) ?? []
        let userLocal = allLocal.filter { $0.authorID == uid }
        print("[SYNC] After sync: \(allLocal.count) total local timelapses, \(userLocal.count) belong to current user (uid: \(uid))")
        if let first = allLocal.first {
            print("[SYNC] Sample timelapse authorID: '\(first.authorID)' vs currentUID: '\(uid)' match: \(first.authorID == uid)")
        }
        
        // One-time data restoration from simulator backup (recovers wiped sessions)
        restoreLostSessionsIfNeeded(uid: uid)
        
        // Recompute stats from all local timelapse records
        recomputeStatsFromTimelapses(uid: uid)
        
        try? modelContext.save()
    }
    
    /// One-time restore of 12 study sessions recovered from simulator SQLite store.
    /// These were lost when the schema migration wiped the local database.
    @MainActor
    private func restoreLostSessionsIfNeeded(uid: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didRestoreLostSessions_v1") else { return }
        
        // Only restore for the original user
        guard uid == "61BB6A49-8A34-4DA1-91DE-FA1617C409CF" else {
            defaults.set(true, forKey: "didRestoreLostSessions_v1")
            return
        }
        
        // Check which session IDs already exist locally to avoid duplicates
        let existingDescriptor = FetchDescriptor<StudyTimelapse>()
        let existingIDs = Set((try? modelContext.fetch(existingDescriptor))?.map { $0.id.uuidString.lowercased() } ?? [])
        
        struct RestoredSession {
            let id: UUID
            let caption: String
            let studyDescription: String
            let subject: String
            let durationSeconds: Int
            let createdAt: Date
            let isLandscape: Bool
            let likeCount: Int
        }
        
        // Apple reference date offset: 978307200 seconds from Unix epoch to 2001-01-01
        let appleEpoch: TimeInterval = 978307200
        
        let sessions: [RestoredSession] = [
            RestoredSession(id: UUID(uuidString: "DE02A214-D35D-4A20-B102-EA76A9E48A8A")!, caption: "lol", studyDescription: "i'm so", subject: "English", durationSeconds: 24, createdAt: Date(timeIntervalSince1970: appleEpoch + 806126671.22), isLandscape: false, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "CEA1AB69-4307-40B8-98D3-103AC3ECBB66")!, caption: "idk", studyDescription: "lol", subject: "Science", durationSeconds: 6, createdAt: Date(timeIntervalSince1970: appleEpoch + 806125574.461), isLandscape: true, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "2C53D5E0-2A7C-4C8E-80C8-0D8794663686")!, caption: "idk", studyDescription: "ok", subject: "Physics", durationSeconds: 16, createdAt: Date(timeIntervalSince1970: appleEpoch + 806125552.161), isLandscape: false, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "17C70489-E389-49CA-AD1F-7A1BD1060AFE")!, caption: "I'm the goat", studyDescription: "idk", subject: "SAT English", durationSeconds: 56, createdAt: Date(timeIntervalSince1970: appleEpoch + 806043213.24), isLandscape: true, likeCount: 1),
            RestoredSession(id: UUID(uuidString: "373F8D08-50DB-431D-AEF6-C3ECA938A241")!, caption: "i'm the goat", studyDescription: "idk", subject: "SAT English", durationSeconds: 124, createdAt: Date(timeIntervalSince1970: appleEpoch + 806041982.706), isLandscape: true, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "BB5E3CC2-99BA-4BC4-A5D0-C4DB76758919")!, caption: "m good ", studyDescription: "idk", subject: "Literature", durationSeconds: 108, createdAt: Date(timeIntervalSince1970: appleEpoch + 806123931.37), isLandscape: true, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "D1D425EC-B5DA-44E2-BB9B-A70EC91CD0DB")!, caption: "sat shi ", studyDescription: "idk", subject: "SAT English", durationSeconds: 171, createdAt: Date(timeIntervalSince1970: appleEpoch + 806097919.808), isLandscape: true, likeCount: 1),
            RestoredSession(id: UUID(uuidString: "42FF8620-1643-49D5-AF80-712DCB12BBF0")!, caption: "lol", studyDescription: "ddss", subject: "Science", durationSeconds: 6, createdAt: Date(timeIntervalSince1970: appleEpoch + 806125299.838), isLandscape: false, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "C9CD022F-49F3-496A-BB8C-CED60331AE30")!, caption: "hhhhh", studyDescription: "g dr hhv", subject: "Science", durationSeconds: 583, createdAt: Date(timeIntervalSince1970: appleEpoch + 806126516.284), isLandscape: true, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "F64B002B-A8EB-4B9E-9B67-B70DCE280F08")!, caption: "idk", studyDescription: "idk", subject: "Physics", durationSeconds: 7, createdAt: Date(timeIntervalSince1970: appleEpoch + 806125767.879), isLandscape: false, likeCount: 1),
            RestoredSession(id: UUID(uuidString: "CDDA0455-0AC0-41A5-8DE9-2CC9D14C9461")!, caption: "a", studyDescription: "lol", subject: "Science", durationSeconds: 6, createdAt: Date(timeIntervalSince1970: appleEpoch + 806124270.737), isLandscape: true, likeCount: 0),
            RestoredSession(id: UUID(uuidString: "6557DC75-BDCF-4629-8E9D-2ECA9C6088B4")!, caption: "dk", studyDescription: "lol", subject: "History", durationSeconds: 35, createdAt: Date(timeIntervalSince1970: appleEpoch + 806126741.404), isLandscape: false, likeCount: 0),
        ]
        
        var restoredCount = 0
        for session in sessions {
            guard !existingIDs.contains(session.id.uuidString.lowercased()) else { continue }
            
            let timelapse = StudyTimelapse(
                authorID: uid,
                authorName: "max c",
                authorAvatarURL: nil,
                caption: session.caption,
                studyDescription: session.studyDescription,
                subject: session.subject,
                durationSeconds: session.durationSeconds,
                videoFileName: nil,
                thumbnailData: nil,
                isLandscape: session.isLandscape
            )
            // Overwrite auto-generated fields with original values
            timelapse.id = session.id
            timelapse.createdAt = session.createdAt
            timelapse.likeCount = session.likeCount
            
            modelContext.insert(timelapse)
            restoredCount += 1
        }
        
        if restoredCount > 0 {
            try? modelContext.save()
            print("[RESTORE] Restored \(restoredCount) lost study sessions")
            
            // Upload restored sessions to Supabase
            let restoredTimelapses = sessions.map { $0.id }
            Task {
                let descriptor = FetchDescriptor<StudyTimelapse>()
                let all = (try? modelContext.fetch(descriptor)) ?? []
                for tl in all where restoredTimelapses.contains(tl.id) {
                    try? await SupabaseService.shared.saveTimelapse(tl)
                }
                print("[RESTORE] Uploaded restored sessions to Supabase")
            }
        }
        
        defaults.set(true, forKey: "didRestoreLostSessions_v1")
        print("[RESTORE] One-time restoration complete (\(restoredCount) new sessions)")
    }
    
    /// Recompute totalStudyMinutes and streakDays from all local timelapse records.
    @MainActor
    private func recomputeStatsFromTimelapses(uid: String) {
        let descriptor = FetchDescriptor<StudyTimelapse>()
        let allTimelapses = (try? modelContext.fetch(descriptor)) ?? []
        let userTimelapses = allTimelapses.filter { $0.authorID == uid }
        guard !userTimelapses.isEmpty else { return }
        
        // Total study minutes
        let totalMinutes = userTimelapses.reduce(0) { $0 + $1.durationSeconds } / 60
        
        // Streak: consecutive calendar days ending today or yesterday
        let calendar = Calendar.current
        let studyDates = Set(userTimelapses.map { calendar.startOfDay(for: $0.createdAt) })
        let today = calendar.startOfDay(for: Date())
        var checkDate = today
        if !studyDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            if !studyDates.contains(checkDate) {
                // No study today or yesterday — streak is 0
                updateProfileStats(uid: uid, minutes: totalMinutes, streak: 0)
                return
            }
        }
        var streak = 0
        while studyDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        
        updateProfileStats(uid: uid, minutes: totalMinutes, streak: streak)
    }
    
    @MainActor
    private func updateProfileStats(uid: String, minutes: Int, streak: Int) {
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        guard let profile = try? modelContext.fetch(descriptor).first else { return }
        
        // Only ever increase — keep max of computed vs stored
        let newMinutes = max(profile.totalStudyMinutes, minutes)
        let newStreak = max(profile.streakDays, streak)
        
        if profile.totalStudyMinutes != newMinutes || profile.streakDays != newStreak {
            profile.totalStudyMinutes = newMinutes
            profile.streakDays = newStreak
            print("[SYNC] Stats recomputed from timelapses: \(newMinutes) min, \(newStreak) day streak")
            
            Task {
                try? await SupabaseService.shared.saveUserProfile(profile)
            }
        }
    }
}

#Preview {
    ContentView(deepLinkTimelapseID: .constant(nil))
        .environment(AuthService.shared)
        .modelContainer(for: [
            UserProfile.self,
            StudyTimelapse.self,
            TimelapseComment.self,
            StudyGroup.self,
            StudySubject.self
        ], inMemory: true)
}
