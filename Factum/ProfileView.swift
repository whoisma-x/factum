//
//  ProfileView.swift
//  Factum
//
//  User profile view with stats and Google sign-in
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var showSignIn = false
    @State private var showEditProfile = false
    @State private var showSettings = false
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var userTimelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Scrollable title row
                    HStack {
                        Text("Profile")
                            .font(FactumTheme.titleFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    
                    if let user = currentUser {
                        profileHeader(user: user)
                        statsGrid(user: user)
                        
                        // Detailed stats link
                        NavigationLink {
                            StatsView()
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(FactumTheme.secondaryText)
                                Text("View Detailed Stats")
                                    .font(FactumTheme.subheadlineFont)
                                    .foregroundStyle(FactumTheme.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(FactumTheme.tertiaryText)
                            }
                            .padding(16)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        studyHistorySection
                        myPostsSection
                    } else if AuthService.shared.isSignedIn {
                        // Signed in but local profile hasn't synced yet
                        VStack(spacing: 16) {
                            Spacer().frame(height: 80)
                            ProgressView()
                                .tint(FactumTheme.accent)
                            Text("Loading profile…")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                    } else {
                        signInPrompt
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(FactumTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                // Sync computed stats to user model and Supabase
                guard let user = currentUser else { return }
                let newMinutes = computedTotalStudyMinutes
                let newStreak = computedStreakDays
                if user.totalStudyMinutes != newMinutes || user.streakDays != newStreak {
                    user.totalStudyMinutes = newMinutes
                    user.streakDays = newStreak
                    // Sync updated stats to Supabase
                    try? await SupabaseService.shared.saveUserProfile(user)
                }
            }
        }
    }
    
    // MARK: - Profile Header
    
    private func profileHeader(user: UserProfile) -> some View {
        VStack(spacing: 14) {
            // Avatar + name side by side
            HStack(spacing: 14) {
                avatarView(name: user.displayName, size: 64, avatarURL: user.avatarURL)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(FactumTheme.titleFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    Text(user.email)
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.tertiaryText)
                    
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button {
                    showEditProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(FactumTheme.secondaryText)
                        .padding(10)
                        .background(FactumTheme.cardBackground)
                        .clipShape(Circle())
                }
            }
            
        }
        .padding(.top, 8)
    }
    
    // MARK: - Computed Stats
    
    /// All-time total study minutes computed from every session
    private var computedTotalStudyMinutes: Int {
        userTimelapses.reduce(0) { $0 + $1.durationSeconds } / 60
    }
    
    /// Streak: consecutive calendar days (ending today or yesterday) with at least one session
    private var computedStreakDays: Int {
        guard !userTimelapses.isEmpty else { return 0 }
        let calendar = Calendar.current
        // Get unique study dates (start of day)
        let studyDates = Set(userTimelapses.map { calendar.startOfDay(for: $0.createdAt) })
        let today = calendar.startOfDay(for: Date())
        
        // Start counting from today; if no session today, try yesterday
        var checkDate = today
        if !studyDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            if !studyDates.contains(checkDate) {
                return 0
            }
        }
        
        var streak = 0
        while studyDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(user: UserProfile) -> some View {
        let totalHours = computedTotalStudyMinutes / 60
        let totalMins = computedTotalStudyMinutes % 60
        
        return HStack(spacing: 0) {
            statCard(value: "\(totalHours)h \(totalMins)m", label: "Total Study")
            statCard(value: "\(userTimelapses.count)", label: "Sessions")
            streakCard(days: computedStreakDays)
        }
    }
    
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(FactumTheme.font(20, weight: .bold))
                .foregroundStyle(FactumTheme.primaryText)
            Text(label)
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private func streakCard(days: Int) -> some View {
        // Flame scales from 14pt (0 days) to 24pt (30+ days)
        let flameSize: CGFloat = min(24, 14 + CGFloat(days) * 0.33)
        // Opacity goes from dim (no streak) to full
        let flameOpacity: Double = days == 0 ? 0.25 : min(1.0, 0.5 + Double(days) * 0.05)
        
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: flameSize))
                    .foregroundStyle(.orange.opacity(flameOpacity))
                Text("\(days)")
                    .font(FactumTheme.font(20, weight: .bold))
                    .foregroundStyle(FactumTheme.primaryText)
            }
            Text("Day Streak")
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Study History
    
    private var studyHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(FactumTheme.headlineFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            // Weekly activity grid — computed from real session data
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let dayNames = ["M", "T", "W", "T", "F", "S", "S"]
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    // Calculate the Monday of this week
                    let weekday = calendar.component(.weekday, from: today)
                    let daysFromMonday = (weekday + 5) % 7 // Monday = 0
                    let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
                    let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: monday)!
                    
                    let dayMinutes = userTimelapses.filter { calendar.isDate(calendar.startOfDay(for: $0.createdAt), inSameDayAs: targetDate) }
                        .reduce(0) { $0 + $1.durationSeconds / 60 }
                    let hasActivity = dayMinutes > 0
                    let maxMinutes = max(1, userTimelapses.map { $0.durationSeconds / 60 }.max() ?? 1)
                    let intensity = hasActivity ? max(0.3, min(1.0, Double(dayMinutes) / Double(maxMinutes))) : 0.0
                    
                    VStack(spacing: 6) {
                        Text(dayNames[dayOffset])
                            .font(FactumTheme.smallFont)
                            .foregroundStyle(FactumTheme.tertiaryText)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasActivity
                                  ? FactumTheme.accent.opacity(intensity)
                                  : FactumTheme.surfaceBackground)
                            .frame(height: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - My Posts
    
    @State private var showAllSessions = false
    
    private var myPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Sessions")
                    .font(FactumTheme.headlineFont)
                    .foregroundStyle(FactumTheme.primaryText)
                
                Spacer()
                
                if !userTimelapses.isEmpty {
                    Button {
                        showAllSessions = true
                    } label: {
                        Text("View All")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.accent)
                    }
                }
            }
            
            if userTimelapses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 30))
                        .foregroundStyle(FactumTheme.tertiaryText)
                    Text("No sessions yet")
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(FactumTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Show recent sessions as full cards (up to 3)
                ForEach(Array(userTimelapses.prefix(3))) { timelapse in
                    TimelapseCardView(timelapse: timelapse)
                }
            }
        }
        .sheet(isPresented: $showAllSessions) {
            AllSessionsView(timelapses: userTimelapses)
        }
    }
    
    // MARK: - Sign In Prompt
    
    private var signInPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)
            
            FactumIcon(size: 80, color: FactumTheme.secondaryText)
            
            Text("Welcome to Factum")
                .font(FactumTheme.titleFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Text("Sign in to track your study sessions\nand connect with friends")
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            // Google Sign-In button
            Button {
                Task {
                    try? await AuthService.shared.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22))
                    Text("Sign in with Google")
                        .font(FactumTheme.subheadlineFont)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var displayName = ""
    @State private var bio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImageData: Data?
    
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Avatar with photo picker
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let avatarImageData, let uiImage = UIImage(data: avatarImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else if let avatarURL = currentUser?.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                default:
                                    Circle()
                                        .fill(FactumTheme.elevated)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(FactumTheme.secondaryText)
                                        )
                                }
                            }
                        } else {
                            Circle()
                                .fill(FactumTheme.elevated)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(FactumTheme.secondaryText)
                                )
                        }
                        
                        Circle()
                            .fill(FactumTheme.accent)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.black)
                            )
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            avatarImageData = data
                        }
                    }
                }
                .padding(.top, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                    
                    TextField("Your name", text: $displayName)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                    
                    TextField("Tell people about yourself", text: $bio)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .background(FactumTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let user = currentUser else { return }
                        user.displayName = displayName
                        user.bio = bio
                        
                        // Save avatar locally (MVP: no cloud upload)
                        if let avatarImageData {
                            let fileName = "avatar_\(user.firebaseUID ?? user.id.uuidString).jpg"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let avatarPath = docs.appendingPathComponent(fileName)
                            try? avatarImageData.write(to: avatarPath)
                            user.avatarURL = avatarPath.absoluteString
                        }
                        
                        // Sync profile changes to Supabase
                        Task {
                            try? await SupabaseService.shared.saveUserProfile(user)
                        }
                        
                        dismiss()
                    }
                    .foregroundStyle(FactumTheme.accent)
                    .font(FactumTheme.font(15, weight: .semibold))
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
        .onAppear {
            if let user = currentUser {
                displayName = user.displayName
                bio = user.bio
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [UserProfile]
    @State private var googlePhotosBackup = GooglePhotosService.shared.isBackupEnabled
    @State private var isRequestingScope = false
    @State private var showScopeError = false
    @State private var scopeErrorMessage = ""
    /// 0 = system, 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode: Int = 2
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    settingsRow(icon: "bell.fill", title: "Notifications")
                    settingsRow(icon: "lock.fill", title: "Privacy")

                    HStack(spacing: 12) {
                        Image(systemName: "paintbrush.fill")
                            .foregroundStyle(FactumTheme.secondaryText)
                            .frame(width: 24)
                        Picker("Appearance", selection: $appearanceMode) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(FactumTheme.cardBackground)
                    NavigationLink {
                        ManageSubjectsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.fill")
                                .foregroundStyle(FactumTheme.secondaryText)
                                .frame(width: 24)
                            Text("Manage Subjects")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.primaryText)
                        }
                    }
                    .listRowBackground(FactumTheme.cardBackground)
                } header: {
                    Text("Preferences")
                        .font(FactumTheme.smallFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(FactumTheme.secondaryText)
                            .frame(width: 24)
                        
                        if isRequestingScope {
                            HStack {
                                Text("Google Photos Backup")
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.primaryText)
                                Spacer()
                                ProgressView()
                                    .tint(FactumTheme.accent)
                            }
                        } else {
                            Toggle(isOn: $googlePhotosBackup) {
                                Text("Google Photos Backup")
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.primaryText)
                            }
                            .tint(FactumTheme.accent)
                        }
                    }
                    .listRowBackground(FactumTheme.cardBackground)
                    .onChange(of: googlePhotosBackup) { _, enabled in
                        if enabled {
                            Task {
                                isRequestingScope = true
                                do {
                                    try await GooglePhotosService.shared.requestPhotosScope()
                                    GooglePhotosService.shared.isBackupEnabled = true
                                } catch {
                                    googlePhotosBackup = false
                                    GooglePhotosService.shared.isBackupEnabled = false
                                    scopeErrorMessage = error.localizedDescription
                                    showScopeError = true
                                }
                                isRequestingScope = false
                            }
                        } else {
                            GooglePhotosService.shared.isBackupEnabled = false
                        }
                    }
                } header: {
                    Text("Backup")
                        .font(FactumTheme.smallFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                
                Section {
                    settingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    settingsRow(icon: "info.circle.fill", title: "About Factum")
                } header: {
                    Text("Support")
                        .font(FactumTheme.smallFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                
                Section {
                    Button {
                        Task {
                            // Save current stats to Supabase before signing out
                            if let user = currentUser {
                                try? await SupabaseService.shared.saveUserProfile(user)
                            }
                            try? await AuthService.shared.signOut()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(FactumTheme.destructive)
                            Text("Sign Out")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.destructive)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FactumTheme.background)
            .alert("Google Photos", isPresented: $showScopeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(scopeErrorMessage)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
        .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
    }
    
    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(FactumTheme.secondaryText)
                .frame(width: 24)
            Text(title)
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FactumTheme.tertiaryText)
        }
        .listRowBackground(FactumTheme.cardBackground)
    }
}

// MARK: - All Sessions View

struct AllSessionsView: View {
    let timelapses: [StudyTimelapse]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(timelapses) { timelapse in
                        TimelapseCardView(timelapse: timelapse)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(FactumTheme.background)
            .navigationTitle("All Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, TimelapseComment.self, StudyGroup.self, StudySubject.self], inMemory: true)
}
