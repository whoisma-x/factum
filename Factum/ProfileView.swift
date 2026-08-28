//
//  ProfileView.swift
//  Pigeon
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
                VStack(spacing: 0) {
                    // Scrollable title row
                    HStack {
                        Text("Profile")
                            .font(PigeonTheme.titleFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(PigeonTheme.secondaryText)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.top, PigeonTheme.spacing12)
                    .padding(.bottom, PigeonTheme.spacing8)
                    
                    if let user = currentUser {
                        profileHeader(user: user)
                            .padding(.bottom, PigeonTheme.spacing16)
                        
                        statsGrid(user: user)
                            .padding(.bottom, PigeonTheme.spacing12)
                        
                        // Detailed stats link
                        NavigationLink {
                            StatsView()
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(PigeonTheme.secondaryText)
                                Text("View Detailed Stats")
                                    .font(PigeonTheme.subheadlineFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            .padding(PigeonTheme.spacing16)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(OrganicRect(base: PigeonTheme.cornerCard))
                            .shadow(color: PigeonTheme.cardShadow, radius: PigeonTheme.cardShadowRadius, x: 0, y: PigeonTheme.cardShadowY)
                        }
                        .overlay {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: StatsCardFrameKey.self,
                                    value: geo.frame(in: .global)
                                )
                            }
                        }
                        .padding(.bottom, PigeonTheme.spacing32)
                        
                        studyHistorySection
                            .padding(.bottom, PigeonTheme.spacing32)
                        
                        myPostsSection
                    } else if AuthService.shared.isSignedIn {
                        // Signed in but local profile hasn't synced yet
                        VStack(spacing: 16) {
                            Spacer().frame(height: 80)
                            ProgressView()
                                .tint(PigeonTheme.accent)
                            Text("Loading profile…")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    } else {
                        signInPrompt
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(PigeonTheme.background)
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
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.accent)
                    }
                    
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button {
                    showEditProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .padding(12)
                        .background(PigeonTheme.cardBackground)
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
        .background(PigeonTheme.cardBackground)
        .clipShape(OrganicRect(base: PigeonTheme.cornerCard))
        .shadow(color: PigeonTheme.cardShadow, radius: PigeonTheme.cardShadowRadius, x: 0, y: PigeonTheme.cardShadowY)
    }
    
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(PigeonTheme.font(18, weight: .bold))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)
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
                    .font(PigeonTheme.font(18, weight: .bold))
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            Text("Day Streak")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Study History
    
    /// Pre-computed weekly activity data to avoid per-cell Calendar work in the body.
    private var weeklyActivity: [(label: String, minutes: Int, intensity: Double)] {
        let dayNames = ["M", "T", "W", "T", "F", "S", "S"]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }

        // Build a lookup of study minutes per day (O(n) single pass)
        var minutesByDay: [Date: Int] = [:]
        for tl in userTimelapses {
            let day = calendar.startOfDay(for: tl.createdAt)
            minutesByDay[day, default: 0] += tl.durationSeconds / 60
        }
        let maxMinutes = max(1, minutesByDay.values.max() ?? 1)

        return (0..<7).map { offset in
            let targetDate = calendar.date(byAdding: .day, value: offset, to: monday)!
            let mins = minutesByDay[targetDate] ?? 0
            let intensity = mins > 0 ? max(0.3, min(1.0, Double(mins) / Double(maxMinutes))) : 0.0
            return (dayNames[offset], mins, intensity)
        }
    }

    private var studyHistorySection: some View {
        VStack(alignment: .leading, spacing: PigeonTheme.spacing12) {
            Text("This Week")
                .pigeonSectionTitle()
            
            HStack(spacing: 6) {
                ForEach(Array(weeklyActivity.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        Text(day.label)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(day.minutes > 0
                                  ? PigeonTheme.accent.opacity(day.intensity)
                                  : PigeonTheme.surfaceBackground)
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
        VStack(alignment: .leading, spacing: PigeonTheme.spacing12) {
            HStack {
                Text("My Sessions")
                    .pigeonSectionTitle()
                
                Spacer()
                
                if !userTimelapses.isEmpty {
                    Button {
                        showAllSessions = true
                    } label: {
                        Text("View All")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.accent)
                    }
                }
            }
            
            if userTimelapses.isEmpty {
                Text("Your recorded sessions will appear here.")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PigeonTheme.spacing16)
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
            
            PigeonIcon(size: 112, color: PigeonTheme.secondaryText)
            
            Text("Welcome to Pigeon")
                .font(PigeonTheme.titleFont)
                .foregroundStyle(PigeonTheme.primaryText)
            
            Text("Sign in to track your study sessions\nand connect with friends")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            // Google Sign-In button
            Button {
                Haptics.medium()
                Task {
                    try? await AuthService.shared.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22))
                    Text("Sign in with Google")
                        .font(PigeonTheme.subheadlineFont)
                }
                .foregroundStyle(PigeonTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PigeonTheme.cardBackground)
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
    @State private var username = ""
    @State private var originalUsername = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImageData: Data?
    @State private var isPrivateAccount = true

    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var usernameChanged: Bool {
        username != originalUsername
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
                                        .fill(PigeonTheme.elevated)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(PigeonTheme.secondaryText)
                                        )
                                }
                            }
                        } else {
                            Circle()
                                .fill(PigeonTheme.elevated)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                )
                        }
                        
                        Circle()
                            .fill(PigeonTheme.accent)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(PigeonTheme.accentText)
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
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    TextField("Your name", text: $displayName)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .tint(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    HStack(spacing: 4) {
                        Text("@")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        TextField("username", text: $username)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                let sanitized = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                if sanitized != newValue { username = sanitized }
                                // If reverted to original, no need to check
                                if sanitized == originalUsername {
                                    usernameAvailable = nil
                                    isCheckingUsername = false
                                    usernameCheckTask?.cancel()
                                    return
                                }
                                usernameAvailable = nil
                                usernameCheckTask?.cancel()
                                guard sanitized.count >= 3 else { return }
                                usernameCheckTask = Task {
                                    isCheckingUsername = true
                                    try? await Task.sleep(for: .milliseconds(400))
                                    guard !Task.isCancelled else { return }
                                    usernameAvailable = try? await SupabaseService.shared.isUsernameAvailable(sanitized)
                                    isCheckingUsername = false
                                }
                            }
                    }
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                usernameChanged && usernameAvailable == true ? Color.green.opacity(0.5) :
                                usernameChanged && usernameAvailable == false ? PigeonTheme.destructive.opacity(0.5) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    
                    if isCheckingUsername {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Checking...")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    } else if usernameChanged, let available = usernameAvailable {
                        Text(available ? "Username available" : "Username taken")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(available ? .green : PigeonTheme.destructive)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    TextField("Tell people about yourself", text: $bio)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Account privacy toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Account")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text(isPrivateAccount
                             ? "Only friends can see your sessions"
                             : "Anyone can see your sessions in the feed")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    Spacer()
                    Toggle("", isOn: $isPrivateAccount)
                        .labelsHidden()
                        .tint(PigeonTheme.accent)
                }
                .padding(14)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding(.horizontal, 16)
            .background(PigeonTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Profile")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let user = currentUser else { return }
                        user.displayName = displayName
                        user.bio = bio
                        user.isPrivate = isPrivateAccount
                        
                        // Save avatar locally (MVP: no cloud upload)
                        if let avatarImageData {
                            let fileName = "avatar_\(user.firebaseUID ?? user.id.uuidString).jpg"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let avatarPath = docs.appendingPathComponent(fileName)
                            try? avatarImageData.write(to: avatarPath)
                            user.avatarURL = avatarPath.absoluteString
                        }
                        
                        // Handle username change
                        let newUsername = username.lowercased()
                        let needsUsernameClaim = usernameChanged && newUsername.count >= 3 && usernameAvailable == true
                        
                        // Sync profile changes to Supabase
                        Task {
                            if needsUsernameClaim {
                                let uid = AuthService.shared.currentUserID
                                let claimed = try? await SupabaseService.shared.claimUsername(newUsername, forUser: uid)
                                if claimed == true {
                                    await MainActor.run {
                                        user.username = newUsername
                                    }
                                }
                            }
                            try? await SupabaseService.shared.saveUserProfile(user)
                        }
                        
                        dismiss()
                    }
                    .foregroundStyle(PigeonTheme.accent)
                    .font(PigeonTheme.font(15, weight: .semibold))
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
        .onAppear {
            if let user = currentUser {
                displayName = user.displayName
                bio = user.bio
                username = user.username ?? ""
                originalUsername = user.username ?? ""
                isPrivateAccount = user.isPrivate
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
    /// 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("autoDimScreen") private var autoDimScreen = false
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsPlaceholderView(title: "Notifications")
                    } label: {
                        settingsRow(icon: "bell.fill", title: "Notifications")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        SettingsPlaceholderView(title: "Privacy")
                    } label: {
                        settingsRow(icon: "lock.fill", title: "Privacy")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)

                    HStack(spacing: 12) {
                        Image(systemName: "paintbrush.fill")
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 28)
                        Picker("Appearance", selection: $appearanceMode) {
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onAppear {
                            let serifFont = UIFont(name: "Georgia", size: 13)
                                ?? UIFont.systemFont(ofSize: 13, weight: .light)
                            UISegmentedControl.appearance().setTitleTextAttributes(
                                [.font: serifFont], for: .normal
                            )
                            UISegmentedControl.appearance().setTitleTextAttributes(
                                [.font: serifFont], for: .selected
                            )
                        }
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        ManageSubjectsView()
                    } label: {
                        settingsRow(icon: "book.fill", title: "Manage Subjects")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 28)
                        Toggle(isOn: $autoDimScreen) {
                            Text("Dim Screen While Recording")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                        .tint(PigeonTheme.accent)
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                } header: {
                    Text("Preferences")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 28)
                        
                        if isRequestingScope {
                            HStack {
                                Text("Google Photos Backup")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                                ProgressView()
                                    .tint(PigeonTheme.accent)
                            }
                        } else {
                            Toggle(isOn: $googlePhotosBackup) {
                                Text("Google Photos Backup")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                            }
                            .tint(PigeonTheme.accent)
                        }
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
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
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    NavigationLink {
                        SettingsPlaceholderView(title: "Help & Support")
                    } label: {
                        settingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        SettingsPlaceholderView(title: "About Pigeon")
                    } label: {
                        settingsRow(icon: "info.circle.fill", title: "About Pigeon")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                } header: {
                    Text("Support")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    Button {
                        Haptics.warning()
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
                                .foregroundStyle(PigeonTheme.destructive)
                            Text("Sign Out")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.destructive)
                        }
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PigeonTheme.background)
            .alert("Google Photos", isPresented: $showScopeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(scopeErrorMessage)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(appearanceMode == 1 ? .light : .dark)
        .onAppear {
            // First time: resolve "system" (0) to the device's actual setting
            if appearanceMode == 0 {
                appearanceMode = UITraitCollection.current.userInterfaceStyle == .dark ? 2 : 1
            }
        }
    }
    
    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PigeonTheme.secondaryText)
                .frame(width: 28)
            Text(title)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
        }
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
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("All Sessions")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
    }
}

// MARK: - Settings Sub-Pages

struct SettingsPlaceholderView: View {
    let title: String
    
    private var icon: String {
        switch title {
        case "Notifications": return "bell.fill"
        case "Privacy": return "lock.shield.fill"
        case "Help & Support": return "envelope.fill"
        default: return "info.circle.fill"
        }
    }
    
    private var description: String {
        switch title {
        case "Notifications":
            return "Notification preferences will let you control study reminders, friend activity, and session alerts."
        case "Privacy":
            return "Privacy settings will let you manage who can see your study sessions and profile information."
        case "Help & Support":
            return "Have a question or found a bug? We'd love to hear from you."
        default:
            return "Pigeon helps you build consistent study habits through timelapses, tracking, and accountability."
        }
    }
    
    var body: some View {
        VStack(spacing: PigeonTheme.spacing24) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(PigeonTheme.secondaryText)
            
            VStack(spacing: PigeonTheme.spacing8) {
                Text(title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                
                Text(description)
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, PigeonTheme.spacing32)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PigeonTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
        }
        .toolbarBackground(PigeonTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, StudyGroup.self, StudySubject.self], inMemory: true)
}
