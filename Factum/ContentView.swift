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
    @Environment(\.colorScheme) private var colorScheme
    
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
                
                // Floating Liquid Glass tab bar
                customTabBar
                    .padding(.bottom, 2)
                    .padding(.horizontal, 16)
                
                // Tutorial coach marks overlay (shown once after first sign-in)
                if showTutorial {
                    TutorialOverlayView(
                        isShowing: $showTutorial,
                        selectedTab: $selectedTab
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
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
        .fullScreenCover(isPresented: $showCamera) {
            TimelapseCameraView()
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
        ("person.2.fill", 1),
        ("video.fill", 2),       // Record (center)
        ("person.3.fill", 3),
        ("person.circle.fill", 4),
    ]
    
    private var customTabBar: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tag) { tab in
                    if tab.tag == 2 {
                        // Center record button
                        Button {
                            showCamera = true
                        } label: {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(FactumTheme.primaryText)
                                .frame(width: 52, height: 52)
                        }
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        .glassEffectID("tab_record", in: tabBarNamespace)
                    } else if tab.tag == 4, let avatarImage = tabBarAvatarImage {
                        // Profile tab with user's avatar
                        Button {
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
                            .frame(width: 52, height: 52)
                            .background {
                                if selectedTab == tab.tag {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(FactumTheme.primaryText.opacity(0.15))
                                        .matchedGeometryEffect(id: "activeTab", in: tabBarNamespace)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Button {
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
                                .frame(width: 52, height: 52)
                                .background {
                                    if selectedTab == tab.tag {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(FactumTheme.primaryText.opacity(0.15))
                                            .matchedGeometryEffect(id: "activeTab", in: tabBarNamespace)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
    }
    
    // MARK: - Local Setup
    
    @MainActor
    private func syncFromCloud() async {
        let uid = authService.currentUserID
        guard !uid.isEmpty else {
            StudySubject.seedDefaultsIfNeeded(context: modelContext)
            return
        }
        
        // Sync user profile from Supabase (creates local profile if needed)
        await SupabaseService.shared.syncUserProfile(uid: uid, context: modelContext)
        
        // Sync study subjects from Supabase, seed defaults if none found
        let hadCloudSubjects = await SupabaseService.shared.syncSubjects(forUser: uid, context: modelContext)
        if !hadCloudSubjects {
            StudySubject.seedDefaultsIfNeeded(context: modelContext)
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
        
        // Recompute stats from all local timelapse records
        recomputeStatsFromTimelapses(uid: uid)
        
        try? modelContext.save()
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
