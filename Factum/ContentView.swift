//
//  ContentView.swift
//  Pigeon
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
    @State private var recoveredSessionDescription: String?
    @State private var showRecoveryAlert = false
    @GestureState private var tabDragOffset: CGFloat = 0
    
    /// Navigable tab tags in order (excludes the center record button).
    private let navigableTabs = [0, 1, 3, 4]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if hasResolvedAuth {
                // Content area — swipeable between tabs
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
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .updating($tabDragOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            guard let currentIndex = navigableTabs.firstIndex(of: selectedTab) else { return }
                            if value.translation.width < -threshold {
                                // Swipe left — next tab
                                let nextIndex = min(currentIndex + 1, navigableTabs.count - 1)
                                if nextIndex != currentIndex {
                                    Haptics.light()
                                    withAnimation(.smooth(duration: 0.3)) {
                                        selectedTab = navigableTabs[nextIndex]
                                    }
                                }
                            } else if value.translation.width > threshold {
                                // Swipe right — previous tab
                                let prevIndex = max(currentIndex - 1, 0)
                                if prevIndex != currentIndex {
                                    Haptics.light()
                                    withAnimation(.smooth(duration: 0.3)) {
                                        selectedTab = navigableTabs[prevIndex]
                                    }
                                }
                            }
                        }
                )
                
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
        .background(PigeonTheme.background)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Retry unsynced sessions every time the app returns to the foreground.
            // This catches sessions that failed while the app was backgrounded or
            // when the user was offline. SyncManager handles backoff so this is cheap.
            guard authService.isSignedIn else { return }
            let uid = authService.currentUserID
            guard !uid.isEmpty else { return }
            Task {
                await SyncManager.shared.retryUnsyncedSessions(uid: uid, context: modelContext)
            }
        }
        .alert("Session Recovered", isPresented: $showRecoveryAlert) {
            Button("OK") {}
        } message: {
            Text("Your last study session was interrupted but we saved it — \(recoveredSessionDescription ?? "study session") has been added to your history.")
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
    
    private enum TabIcon {
        case system(String)
        case asset(String)
    }

    private let tabs: [(icon: TabIcon, tag: Int)] = [
        (.asset("NestIcon"), 0),              // Home
        (.asset("Pigeon2Icon"), 1),            // Friends
        (.system("video.fill"), 2),            // Record (center)
        (.asset("Pigeon3Icon"), 3),            // Groups
        (.asset("Pigeon1Icon"), 4),            // Profile (solo pigeon)
    ]

    @ViewBuilder
    private func tabIcon(for icon: TabIcon, isSelected: Bool) -> some View {
        let color = isSelected ? PigeonTheme.primaryText : PigeonTheme.secondaryText
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
        case .asset(let name):
            let size: CGFloat = name == "NestIcon" ? 42 : 34
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(.bottom, 2)
                .foregroundStyle(color)
        }
    }
    
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
                            tabIcon(for: tab.icon, isSelected: true)
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
                                            selectedTab == tab.tag ? PigeonTheme.primaryText : .clear,
                                            lineWidth: 2
                                        )
                                )
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if selectedTab == tab.tag {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(PigeonTheme.primaryText.opacity(0.15))
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
                            tabIcon(for: tab.icon, isSelected: selectedTab == tab.tag)
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if selectedTab == tab.tag {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(PigeonTheme.primaryText.opacity(0.15))
                                            .matchedGeometryEffect(id: "activeTab", in: tabBarNamespace)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 24))
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
        print("[SYNC] ===== SYNC STARTED for UID: \(uid) =====")
        
        // Recover any interrupted study session before syncing
        if let description = await SyncManager.shared.recoverInterruptedSession(uid: uid, context: modelContext) {
            recoveredSessionDescription = description
            showRecoveryAlert = true
        }
        
        // Sync user profile from Supabase (creates local profile if needed)
        await SupabaseService.shared.syncUserProfile(uid: uid, context: modelContext)
        
        // Ping presence so friends see us as online
        await SupabaseService.shared.updatePresence(uid: uid, isStudying: false, currentSubject: nil)
        
        // Log the synced profile stats for debugging
        let profileCheck = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        if let profile = try? modelContext.fetch(profileCheck).first {
            print("[SYNC] Profile synced: '\(profile.displayName)' | totalStudyMinutes=\(profile.totalStudyMinutes) | streak=\(profile.streakDays)")
        }
        
        // One-time migration: the first user to log in on this device gets
        // their local subjects pushed to Supabase. This preserves subjects
        // created before cloud sync existed. Runs once per device.
        let migrationKey = "pigeon_subjects_pushed_to_cloud"
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
        
        // Sync friends' timelapses into local store so they appear in the feed
        let profileDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        let friendUIDs = (try? modelContext.fetch(profileDescriptor).first?.friendUIDs) ?? []
        if !friendUIDs.isEmpty {
            do {
                let friendRows = try await SupabaseService.shared.fetchFeed(friendUIDs: friendUIDs)
                let existingDescriptor = FetchDescriptor<StudyTimelapse>()
                let existingIDs = Set((try? modelContext.fetch(existingDescriptor))?.map { $0.id } ?? [])
                var friendInserted = 0
                for row in friendRows where !existingIDs.contains(row.id) {
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
                    if let segments = row.subjectSegmentsJson {
                        timelapse.subjectSegmentsJSON = segments
                    }
                    if let leaves = row.appLeaveCount {
                        timelapse.appLeaveCount = leaves
                    }
                    if let offTask = row.offTaskSeconds {
                        timelapse.offTaskSeconds = offTask
                    }
                    modelContext.insert(timelapse)
                    friendInserted += 1
                }
                if friendInserted > 0 {
                    print("[SYNC] Inserted \(friendInserted) friend timelapses into local store")
                }
            } catch {
                print("[SYNC] Friend feed sync failed: \(error)")
            }
        }
        
        // Verify what we have locally after sync
        let checkDescriptor = FetchDescriptor<StudyTimelapse>()
        let allLocal = (try? modelContext.fetch(checkDescriptor)) ?? []
        let userLocal = allLocal.filter { $0.authorID == uid }
        print("[SYNC] After sync: \(allLocal.count) total local timelapses, \(userLocal.count) belong to current user (uid: \(uid))")
        if let first = allLocal.first {
            print("[SYNC] Sample timelapse authorID: '\(first.authorID)' vs currentUID: '\(uid)' match: \(first.authorID == uid)")
        }
        
        // Retry uploading any sessions that failed to sync to Supabase.
        // SyncManager handles exponential backoff and per-session retry tracking,
        // ensuring sessions are eventually backed up even under poor network.
        await SyncManager.shared.retryUnsyncedSessions(uid: uid, context: modelContext)
        
        // One-time seed of SAT study sessions for maxl18chen account
        await seedSATSessionsIfNeeded(uid: uid)
        
        // One-time data restoration from simulator backup (recovers wiped sessions)
        restoreLostSessionsIfNeeded(uid: uid)
        
        // Recompute stats from all local timelapse records
        recomputeStatsFromTimelapses(uid: uid)
        
        try? modelContext.save()
    }
    
    /// One-time seed of SAT study sessions for the maxl18chen account.
    /// 41 sessions: 45h SAT English + 15h SAT Math, Aug 5–22 2026.
    @MainActor
    private func seedSATSessionsIfNeeded(uid: String) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didSeedSATSessions_v1") else { return }
        guard uid == "61BB6A49-8A34-4DA1-91DE-FA1617C409CF" else {
            defaults.set(true, forKey: "didSeedSATSessions_v1")
            return
        }
        
        let calendar = Calendar.current
        // Aug 5, 2026 to Aug 22, 2026
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        
        struct SessionDef {
            let dayOffset: Int   // days from Aug 5
            let hour: Int        // start hour
            let minute: Int
            let duration: Int    // seconds
            let subject: String
            let caption: String
            let description: String
        }
        
        // 41 sessions spread across 18 days (Aug 5–22)
        // SAT English: 27 sessions totaling 162,000s (45h exactly)
        // SAT Math: 14 sessions totaling 54,000s (15h exactly)
        let sessions: [SessionDef] = [
            // Aug 5 (Tue) — 3 sessions
            SessionDef(dayOffset: 0, hour: 10, minute: 15, duration: 6200, subject: "SAT English", caption: "reading passages", description: "practice test 1 reading section"),
            SessionDef(dayOffset: 0, hour: 14, minute: 30, duration: 5400, subject: "SAT English", caption: "grammar drills", description: "writing and language practice"),
            SessionDef(dayOffset: 0, hour: 19, minute: 45, duration: 3400, subject: "SAT Math", caption: "algebra review", description: "heart of algebra problems"),
            // Aug 6 (Wed) — 2 sessions
            SessionDef(dayOffset: 1, hour: 9, minute: 0, duration: 7200, subject: "SAT English", caption: "full reading section", description: "timed practice test 2 reading"),
            SessionDef(dayOffset: 1, hour: 16, minute: 20, duration: 3800, subject: "SAT Math", caption: "problem solving", description: "data analysis questions"),
            // Aug 7 (Thu) — 3 sessions
            SessionDef(dayOffset: 2, hour: 8, minute: 30, duration: 6300, subject: "SAT English", caption: "vocab in context", description: "evidence based reading practice"),
            SessionDef(dayOffset: 2, hour: 13, minute: 0, duration: 5800, subject: "SAT English", caption: "writing section", description: "expression of ideas + standard english"),
            SessionDef(dayOffset: 2, hour: 20, minute: 0, duration: 3600, subject: "SAT Math", caption: "geometry grind", description: "additional topics in math"),
            // Aug 8 (Fri) — 2 sessions
            SessionDef(dayOffset: 3, hour: 11, minute: 0, duration: 7600, subject: "SAT English", caption: "practice test 3", description: "full english section timed run"),
            SessionDef(dayOffset: 3, hour: 18, minute: 30, duration: 4200, subject: "SAT Math", caption: "passport to advanced", description: "advanced math problems"),
            // Aug 9 (Sat) — 3 sessions
            SessionDef(dayOffset: 4, hour: 9, minute: 0, duration: 6400, subject: "SAT English", caption: "reading comprehension", description: "science and history passages"),
            SessionDef(dayOffset: 4, hour: 14, minute: 0, duration: 6800, subject: "SAT English", caption: "writing timed", description: "full writing section practice test 4"),
            SessionDef(dayOffset: 4, hour: 19, minute: 30, duration: 4800, subject: "SAT Math", caption: "calculator section", description: "section 4 full practice"),
            // Aug 10 (Sun) — 2 sessions
            SessionDef(dayOffset: 5, hour: 10, minute: 30, duration: 6000, subject: "SAT English", caption: "error review", description: "reviewing wrong answers from test 3"),
            SessionDef(dayOffset: 5, hour: 15, minute: 0, duration: 4200, subject: "SAT Math", caption: "no calculator", description: "section 3 practice no calc"),
            // Aug 11 (Mon) — 2 sessions
            SessionDef(dayOffset: 6, hour: 9, minute: 15, duration: 6200, subject: "SAT English", caption: "paired passages", description: "dual passage comparison drills"),
            SessionDef(dayOffset: 6, hour: 17, minute: 0, duration: 5800, subject: "SAT English", caption: "command of evidence", description: "evidence support questions"),
            // Aug 12 (Tue) — 3 sessions
            SessionDef(dayOffset: 7, hour: 8, minute: 45, duration: 7500, subject: "SAT English", caption: "practice test 5", description: "full timed reading + writing"),
            SessionDef(dayOffset: 7, hour: 15, minute: 30, duration: 3800, subject: "SAT Math", caption: "quadratics", description: "passport to advanced math quadratics"),
            SessionDef(dayOffset: 7, hour: 20, minute: 15, duration: 3800, subject: "SAT English", caption: "vocab review", description: "words in context flash cards + practice"),
            // Aug 13 (Wed) — 2 sessions
            SessionDef(dayOffset: 8, hour: 10, minute: 0, duration: 6200, subject: "SAT English", caption: "rhetoric questions", description: "purpose and structure questions"),
            SessionDef(dayOffset: 8, hour: 16, minute: 45, duration: 4200, subject: "SAT Math", caption: "functions + graphs", description: "function notation and graph analysis"),
            // Aug 14 (Thu) — 2 sessions
            SessionDef(dayOffset: 9, hour: 9, minute: 30, duration: 5400, subject: "SAT English", caption: "synthesis practice", description: "informational graphics + reading"),
            SessionDef(dayOffset: 9, hour: 14, minute: 0, duration: 6000, subject: "SAT English", caption: "sentence structure", description: "run-ons fragments and comma splices"),
            // Aug 15 (Fri) — 2 sessions
            SessionDef(dayOffset: 10, hour: 11, minute: 0, duration: 6200, subject: "SAT English", caption: "timed reading", description: "4 passages in 52 minutes practice"),
            SessionDef(dayOffset: 10, hour: 17, minute: 30, duration: 4000, subject: "SAT Math", caption: "statistics review", description: "mean median mode and data scatter"),
            // Aug 16 (Sat) — 3 sessions
            SessionDef(dayOffset: 11, hour: 9, minute: 0, duration: 7600, subject: "SAT English", caption: "practice test 6", description: "full english sections back to back"),
            SessionDef(dayOffset: 11, hour: 15, minute: 0, duration: 4400, subject: "SAT Math", caption: "word problems", description: "setting up equations from context"),
            SessionDef(dayOffset: 11, hour: 20, minute: 30, duration: 3400, subject: "SAT English", caption: "quick review", description: "going over test 6 mistakes"),
            // Aug 17 (Sun) — 1 session
            SessionDef(dayOffset: 12, hour: 12, minute: 0, duration: 6000, subject: "SAT English", caption: "rest day reading", description: "light practice on history passages"),
            // Aug 18 (Mon) — 2 sessions
            SessionDef(dayOffset: 13, hour: 9, minute: 0, duration: 6500, subject: "SAT English", caption: "science passages", description: "natural science reading intensive"),
            SessionDef(dayOffset: 13, hour: 15, minute: 30, duration: 4200, subject: "SAT Math", caption: "ratios and percents", description: "problem solving and data analysis"),
            // Aug 19 (Tue) — 2 sessions
            SessionDef(dayOffset: 14, hour: 10, minute: 0, duration: 6800, subject: "SAT English", caption: "writing conventions", description: "punctuation and usage rules"),
            SessionDef(dayOffset: 14, hour: 17, minute: 0, duration: 3600, subject: "SAT Math", caption: "linear equations", description: "systems of equations practice"),
            // Aug 20 (Wed) — 2 sessions
            SessionDef(dayOffset: 15, hour: 9, minute: 30, duration: 6200, subject: "SAT English", caption: "passage analysis", description: "social science and literature passages"),
            SessionDef(dayOffset: 15, hour: 16, minute: 0, duration: 4200, subject: "SAT English", caption: "final grammar", description: "last grammar rules review"),
            // Aug 21 (Thu) — 2 sessions
            SessionDef(dayOffset: 16, hour: 10, minute: 0, duration: 5700, subject: "SAT English", caption: "mock test", description: "practice test 7 english full"),
            SessionDef(dayOffset: 16, hour: 18, minute: 0, duration: 3400, subject: "SAT Math", caption: "trig basics", description: "soh cah toa and unit circle"),
            // Aug 22 (Fri) — 3 sessions
            SessionDef(dayOffset: 17, hour: 9, minute: 0, duration: 6000, subject: "SAT English", caption: "last cram reading", description: "final reading section timed run"),
            SessionDef(dayOffset: 17, hour: 14, minute: 15, duration: 4800, subject: "SAT English", caption: "writing wrap up", description: "writing section final practice"),
            SessionDef(dayOffset: 17, hour: 19, minute: 0, duration: 2400, subject: "SAT Math", caption: "final review", description: "going over all math weak spots"),
        ]
        
        let existingDescriptor = FetchDescriptor<StudyTimelapse>()
        let existingIDs = Set((try? modelContext.fetch(existingDescriptor))?.map { $0.id } ?? [])
        
        var insertedCount = 0
        for session in sessions {
            let sessionDate = calendar.date(bySettingHour: session.hour, minute: session.minute, second: 0,
                                            of: calendar.date(byAdding: .day, value: session.dayOffset, to: startDate)!)!
            
            let timelapse = StudyTimelapse(
                authorID: uid,
                authorName: "max c",
                authorAvatarURL: nil,
                caption: session.caption,
                studyDescription: session.description,
                subject: session.subject,
                durationSeconds: session.duration,
                videoFileName: nil,
                thumbnailData: nil,
                isLandscape: false
            )
            timelapse.createdAt = sessionDate
            
            guard !existingIDs.contains(timelapse.id) else { continue }
            modelContext.insert(timelapse)
            insertedCount += 1
        }
        
        if insertedCount > 0 {
            try? modelContext.save()
            print("[SEED] Inserted \(insertedCount) SAT study sessions")
            
            // Upload all to Supabase
            let allDescriptor = FetchDescriptor<StudyTimelapse>()
            let allLocal = (try? modelContext.fetch(allDescriptor)) ?? []
            let newSessions = allLocal.filter { !$0.cloudSynced && $0.authorID == uid }
            for tl in newSessions {
                do {
                    try await SupabaseService.shared.saveTimelapse(tl)
                    tl.cloudSynced = true
                } catch {
                    print("[SEED] Failed to upload session: \(error.localizedDescription)")
                }
            }
            try? modelContext.save()
            print("[SEED] Uploaded seeded sessions to Supabase")
        }
        
        defaults.set(true, forKey: "didSeedSATSessions_v1")
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

        if profile.totalStudyMinutes != minutes || profile.streakDays != streak {
            profile.totalStudyMinutes = minutes
            profile.streakDays = streak
            print("[SYNC] Stats recomputed from timelapses: \(minutes) min, \(streak) day streak")
        }

        // Always push stats to cloud so all devices see the same numbers
        Task {
            try? await SupabaseService.shared.saveUserProfile(profile)
        }
    }
}

#Preview {
    ContentView(deepLinkTimelapseID: .constant(nil))
        .environment(AuthService.shared)
        .modelContainer(for: [
            UserProfile.self,
            StudyTimelapse.self,
            StudyGroup.self,
            StudySubject.self
        ], inMemory: true)
}
