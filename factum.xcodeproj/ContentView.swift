//
//  ContentView.swift
//  Factum
//
//  Created by Max on 7/11/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @State private var selectedTab = 0
    @State private var showCamera = false
    @State private var showOnboarding = false
    @Namespace private var tabBarNamespace
    
    var body: some View {
        ZStack(alignment: .bottom) {
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
                .padding(.horizontal, 16)
                .padding(.bottom, -16)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(FactumTheme.background)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCamera) {
            TimelapseCameraView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if !signedIn && !authService.isLoading {
                showOnboarding = true
            }
        }
        .onChange(of: authService.isLoading) { _, loading in
            if !loading && !authService.isSignedIn {
                showOnboarding = true
            }
        }
    }
    
    // MARK: - Custom Tab Bar
    
    private var customTabBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                tabBarItem(icon: "house.fill", label: "Feed", tag: 0)
                tabBarItem(icon: "person.2.fill", label: "Friends", tag: 1)
                
                // Center record button
                Button {
                    showCamera = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(FactumTheme.accent)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "video.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("record", in: tabBarNamespace)
                
                tabBarItem(icon: "person.3.fill", label: "Groups", tag: 3)
                tabBarItem(icon: "person.circle.fill", label: "Profile", tag: 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
        }
    }
    
    private func tabBarItem(icon: String, label: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(
                        selectedTab == tag
                        ? FactumTheme.primaryText
                        : FactumTheme.tertiaryText
                    )
                
                Text(label)
                    .font(FactumTheme.smallFont)
                    .foregroundStyle(
                        selectedTab == tag
                        ? FactumTheme.primaryText
                        : FactumTheme.tertiaryText
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(AuthService.shared)
        .modelContainer(for: [
            UserProfile.self,
            StudyTimelapse.self,
            TimelapseComment.self,
            StudyGroup.self,
            StudySubject.self
        ], inMemory: true)
}
